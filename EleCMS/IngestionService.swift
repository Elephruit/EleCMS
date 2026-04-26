import Foundation
import Darwin
import SQLite3

let SQLITE_STATIC_PTR = unsafeBitCast(0, to: sqlite3_destructor_type.self)

final class IngestionService {
    private let store: DataStore

    init(dataStore: DataStore) {
        self.store = dataStore
    }

    func ingestCPSC(enrollmentURL: URL, contractsURL: URL, year: Int, month: Int) async throws {
        let overallStart = Date()
        let periodID = try store.getPeriodID(year: year, month: month)
        print("DEBUG: Starting ingestion for periodID: \(periodID) (\(year)-\(month))")
        
        // Optimize for massive bulk loading
        try store.database.execute(sql: "PRAGMA synchronous = OFF; PRAGMA journal_mode = OFF; PRAGMA cache_size = -1000000; PRAGMA temp_store = MEMORY; PRAGMA locking_mode = EXCLUSIVE;")
        try store.database.execute(sql: """
            DROP INDEX IF EXISTS idx_stg_enr_join;
            DROP INDEX IF EXISTS idx_stg_enr_geo;
            DROP INDEX IF EXISTS idx_stg_con_join;
        """)
        try store.database.execute(sql: "DELETE FROM staging_enrollment; DELETE FROM staging_contracts;")
        
        let eMapping = try await detectCPSCColumns(url: enrollmentURL)
        let cMapping = try await detectContractColumns(url: contractsURL)
        
        print("DEBUG: [1/4] Ultra-Fast Enrollment Ingestion...")
        let eStart = Date()
        try fastBareMetalStream(url: enrollmentURL, table: "staging_enrollment", mapping: eMapping, filterEnrollment: true)
        print("DEBUG: Enrollment took \(Date().timeIntervalSince(eStart))s")
        
        print("DEBUG: [2/4] Contract Ingestion...")
        let cStart = Date()
        try fastBareMetalStream(url: contractsURL, table: "staging_contracts", mapping: cMapping, filterEnrollment: false)
        print("DEBUG: Contract took \(Date().timeIntervalSince(cStart))s")
        
        print("DEBUG: [3/4] Indexing...")
        let idxStart = Date()
        try store.database.execute(sql: """
            CREATE INDEX idx_stg_enr_join ON staging_enrollment(plan_id, contract_id);
            CREATE INDEX idx_stg_enr_geo ON staging_enrollment(county, state);
            CREATE INDEX idx_stg_con_join ON staging_contracts(plan_id, contract_id);
        """)
        print("DEBUG: Indexing took \(Date().timeIntervalSince(idxStart))s")
        
        print("DEBUG: [4/4] Merging...")
        let mergeStart = Date()
        let sql = DBSchema.mergeStagingToFinal.replacingOccurrences(of: ":period_id", with: "\(periodID)")
        try store.database.execute(sql: "BEGIN TRANSACTION; \(sql) COMMIT;")
        print("DEBUG: Merge took \(Date().timeIntervalSince(mergeStart))s")
        
        try store.database.execute(sql: "PRAGMA synchronous = NORMAL; PRAGMA journal_mode = WAL; PRAGMA locking_mode = NORMAL;")
        let count = try store.database.query(sql: "SELECT COUNT(*) as c FROM enrollment_records WHERE period_id = \(periodID)")
        print("DEBUG: Total Records in Dashboard: \(count.first?["c"] ?? 0)")
        print("DEBUG: --- OVERALL TIME: \(Date().timeIntervalSince(overallStart))s ---")
    }

    private func fastBareMetalStream(url: URL, table: String, mapping: [String: Int], filterEnrollment: Bool) throws {
        let cols: [String] = table == "staging_enrollment" 
            ? ["contract_id", "plan_id", "state", "county", "enrollment"]
            : ["contract_id", "plan_id", "organization_type", "plan_type", "offers_part_d", "organization_name", "organization_marketing_name", "plan_name", "parent_organization", "contract_effective_date"]

        let colIndices = cols.map { mapping[$0] ?? -1 }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let sql = "INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(cols.map { _ in "?" }.joined(separator: ",")))"
        let stmt = try store.database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }
        
        try store.database.execute(sql: "BEGIN TRANSACTION;")
        
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let size = bytes.count
            var lineStart = 0
            var isHeader = true
            var rowCount = 0
            var skippedCount = 0
            var fieldOffsets = [(start: Int, len: Int)](repeating: (0, 0), count: 32)
            
            while lineStart < size {
                let remaining = size - lineStart
                let newline = memchr(ptr.advanced(by: lineStart), 10, remaining)
                let rawLineEnd = newline.map { ptr.distance(to: $0.assumingMemoryBound(to: UInt8.self)) } ?? size
                let nextLineStart = newline == nil ? size : rawLineEnd + 1
                let lineEnd = rawLineEnd > lineStart && ptr[rawLineEnd - 1] == 13 ? rawLineEnd - 1 : rawLineEnd
                
                if lineEnd > lineStart {
                    if isHeader { isHeader = false }
                    else {
                        let skipped = filterEnrollment && isSuppressedEnrollment(ptr: ptr, s: lineStart, e: lineEnd)
                        if skipped {
                            skippedCount += 1
                        } else {
                            let fCount = parseFieldsFast(ptr: ptr, s: lineStart, e: lineEnd, offsets: &fieldOffsets)
                            _ = sqlite3_reset(stmt)
                            for (targetIdx, csvIdx) in colIndices.enumerated() {
                                if csvIdx >= 0 && csvIdx < fCount {
                                    let off = fieldOffsets[csvIdx]
                                    if off.len > 0 {
                                        let fieldPtr = ptr.advanced(by: off.start)
                                        fieldPtr.withMemoryRebound(to: Int8.self, capacity: off.len) { int8Ptr in
                                            _ = sqlite3_bind_text(stmt, Int32(targetIdx + 1), int8Ptr, Int32(off.len), SQLITE_STATIC_PTR)
                                        }
                                    } else { _ = sqlite3_bind_null(stmt, Int32(targetIdx + 1)) }
                                } else { _ = sqlite3_bind_null(stmt, Int32(targetIdx + 1)) }
                            }
                            _ = sqlite3_step(stmt)
                            rowCount += 1
                        }
                    }
                }
                
                lineStart = nextLineStart
            }
            print("DEBUG: \(table) Summary -> Inserted: \(rowCount), Skipped (*): \(skippedCount)")
        }
        try store.database.execute(sql: "COMMIT;")
    }

    private func isSuppressedEnrollment(ptr: UnsafePointer<UInt8>, s: Int, e: Int) -> Bool {
        // CMS enrollment is the final column in CPSC enrollment exports.
        var lastComma = e - 1
        while lastComma > s && ptr[lastComma] != 44 { lastComma -= 1 }
        
        var firstCharIdx = lastComma + 1
        while firstCharIdx < e && ptr[firstCharIdx] <= 32 { firstCharIdx += 1 }
        if firstCharIdx >= e { return false }
        
        let c1 = ptr[firstCharIdx]
        if c1 == 42 { return true }
        return c1 == 34 && firstCharIdx + 1 < e && ptr[firstCharIdx + 1] == 42
    }

    private func parseFieldsFast(ptr: UnsafePointer<UInt8>, s: Int, e: Int, offsets: inout [(start: Int, len: Int)]) -> Int {
        var count = 0; var cur = s; var q = false
        for i in s..<e {
            if ptr[i] == 34 { q.toggle() }
            else if ptr[i] == 44 && !q {
                if count < offsets.count {
                    var fs = cur; var fe = i
                    while fs < fe && (ptr[fs] <= 32 || ptr[fs] == 34) { fs += 1 }
                    while fe > fs && (ptr[fe-1] <= 32 || ptr[fe-1] == 34) { fe -= 1 }
                    offsets[count] = (fs, fe - fs); count += 1
                }
                cur = i + 1
            }
        }
        if count < offsets.count {
            var fs = cur; var fe = e
            while fs < fe && (ptr[fs] <= 32 || ptr[fs] == 34) { fs += 1 }
            while fe > fs && (ptr[fe-1] <= 32 || ptr[fe-1] == 34) { fe -= 1 }
            offsets[count] = (fs, fe - fs); count += 1
        }
        return count
    }

    private func detectCPSCColumns(url: URL) async throws -> [String: Int] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 4096),
              let firstLine = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first else { return [:] }
        let headers = parseCSVLine(firstLine); var mapping: [String: Int] = [:]
        for (i, h) in headers.enumerated() {
            let c = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if c.contains("contract") && (c.contains("number") || c.contains("id")) { mapping["contract_id"] = i }
            else if c.contains("plan") && (c.contains("id") || c.contains("pbp")) { mapping["plan_id"] = i }
            else if cleanHeader(c) == "state" { mapping["state"] = i }
            else if cleanHeader(c) == "county" { mapping["county"] = i }
            else if cleanHeader(c) == "enrollment" { mapping["enrollment"] = i }
        }
        return mapping
    }

    private func cleanHeader(_ h: String) -> String {
        return h.trimmingCharacters(in: .init(charactersIn: "\" ")).lowercased()
    }

    private func detectContractColumns(url: URL) async throws -> [String: Int] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 4096),
              let firstLine = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first else { return [:] }
        let headers = parseCSVLine(firstLine); var mapping: [String: Int] = [:]
        for (i, h) in headers.enumerated() {
            let c = h.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if c.contains("contract") && (c.contains("number") || c.contains("id")) { mapping["contract_id"] = i }
            else if c.contains("plan") && (c.contains("id") || c.contains("pbp")) { mapping["plan_id"] = i }
            else if c.contains("organization") && c.contains("type") { mapping["organization_type"] = i }
            else if c.contains("plan") && c.contains("type") { mapping["plan_type"] = i }
            else if c.contains("part") && c.contains("d") { mapping["offers_part_d"] = i }
            else if c.contains("organization") && c.contains("marketing") { mapping["organization_marketing_name"] = i }
            else if c.contains("organization") && c.contains("name") { mapping["organization_name"] = i }
            else if c.contains("plan") && c.contains("name") { mapping["plan_name"] = i }
            else if c.contains("parent") { mapping["parent_organization"] = i }
            else if c.contains("effective") { mapping["contract_effective_date"] = i }
        }
        return mapping
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var res: [String] = []; var cur = ""; var q = false
        for c in line {
            if c == "\"" { q.toggle() }
            else if c == "," && !q { res.append(cur); cur = "" }
            else { cur.append(c) }
        }
        res.append(cur); return res
    }

    func ingestLandscape(url: URL) async throws {
        try store.database.execute(sql: "DELETE FROM staging_landscape")
        let m = ["contract_id": 0, "plan_id": 1, "carrier_name": 2, "plan_name": 3, "plan_type": 4, "monthly_premium": 5, "deductible": 6]
        try fastBareMetalStream(url: url, table: "staging_landscape", mapping: m, filterEnrollment: false)
    }
}
