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
        
        try store.database.execute(sql: "PRAGMA synchronous = OFF; PRAGMA journal_mode = OFF; PRAGMA cache_size = -1000000; PRAGMA temp_store = MEMORY; PRAGMA locking_mode = EXCLUSIVE;")
        try store.database.execute(sql: "DROP TABLE IF EXISTS staging_enrollment; DROP TABLE IF EXISTS staging_contracts;")
        try store.database.execute(sql: DBSchema.createTables)
        
        let eMapping = try await detectCPSCColumns(url: enrollmentURL)
        let cMapping = try await detectContractColumns(url: contractsURL)
        
        print("DEBUG: [1/4] Ultra-Fast Enrollment Ingestion...")
        let eStart = Date()
        try fastBareMetalStream(url: enrollmentURL, table: "staging_enrollment", mapping: eMapping, filterEnrollment: true, skipRows: 1)
        print("DEBUG: Enrollment took \(Date().timeIntervalSince(eStart))s")
        
        print("DEBUG: [2/4] Contract Ingestion...")
        let cStart = Date()
        try fastBareMetalStream(url: contractsURL, table: "staging_contracts", mapping: cMapping, filterEnrollment: false, skipRows: 1)
        print("DEBUG: Contract took \(Date().timeIntervalSince(cStart))s")
        
        print("DEBUG: [3/4] Indexing...")
        let idxStart = Date()
        try store.database.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_stg_enr_join ON staging_enrollment(plan_id, contract_id);
            CREATE INDEX IF NOT EXISTS idx_stg_enr_geo ON staging_enrollment(county, state);
            CREATE INDEX IF NOT EXISTS idx_stg_con_join ON staging_contracts(plan_id, contract_id);
        """)
        print("DEBUG: Indexing took \(Date().timeIntervalSince(idxStart))s")
        
        print("DEBUG: [4/4] Merging...")
        let mergeStart = Date()
        let sql = DBSchema.mergeStagingToFinal.replacingOccurrences(of: ":period_id", with: "\(periodID)")
        try store.database.execute(sql: "BEGIN TRANSACTION; \(sql) COMMIT;")
        print("DEBUG: Merge took \(Date().timeIntervalSince(mergeStart))s")
        
        try store.database.execute(sql: "PRAGMA synchronous = NORMAL; PRAGMA journal_mode = WAL; PRAGMA locking_mode = NORMAL;")
        let count = try store.database.query(sql: "SELECT COUNT(*) as c FROM enrollment_records WHERE period_id = \(periodID)")
        print("DEBUG: Total Records Merged: \(count.first?["c"] ?? 0)")
        print("DEBUG: --- OVERALL TIME: \(Date().timeIntervalSince(overallStart))s ---")
    }

    func ingestLandscape(url: URL, year: Int) async throws {
        print("DEBUG: Starting landscape ingestion from \(url.lastPathComponent) for year \(year)")
        try store.database.execute(sql: "PRAGMA synchronous = OFF; PRAGMA journal_mode = OFF; PRAGMA cache_size = -1000000; PRAGMA temp_store = MEMORY; PRAGMA locking_mode = EXCLUSIVE;")
        
        try store.database.execute(sql: "DROP TABLE IF EXISTS staging_landscape;")
        try store.database.execute(sql: DBSchema.createTables)
        
        let (mapping, headerRowIndex) = try await detectLandscapeColumns(url: url)
        if mapping.isEmpty { return }
        
        try fastBareMetalStream(url: url, table: "staging_landscape", mapping: mapping, filterEnrollment: false, skipRows: headerRowIndex + 1)
        
        let sql = DBSchema.mergeLandscapeToFinal.replacingOccurrences(of: ":year", with: "\(year)")
        try store.database.execute(sql: "BEGIN TRANSACTION; \(sql) COMMIT;")
        try store.database.execute(sql: "DELETE FROM staging_landscape;")
        try store.database.execute(sql: "PRAGMA synchronous = NORMAL; PRAGMA journal_mode = WAL; PRAGMA locking_mode = NORMAL;")
    }

    private func detectLandscapeColumns(url: URL) async throws -> (mapping: [String: Int], rowIndex: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 65536),
              let content = String(data: data, encoding: .utf8) else { return ([:], 0) }
        
        let lines = content.components(separatedBy: .newlines)
        for (rowIndex, line) in lines.enumerated() {
            let headers = parseCSVLine(line)
            var tempMapping: [String: Int] = [:]
            var foundKeyColumn = false
            for (i, h) in headers.enumerated() {
                let clean = h.trimmingCharacters(in: .init(charactersIn: "\" ")).lowercased()
                if (clean.contains("contract") && clean.contains("id")) || (clean == "contract id") { tempMapping["contract_id"] = i; foundKeyColumn = true }
                else if (clean.contains("plan") && clean.contains("id")) || (clean == "plan id") { tempMapping["plan_id"] = i; foundKeyColumn = true }
                else if clean.contains("organization") && clean.contains("name") { tempMapping["carrier_name"] = i }
                else if clean.contains("plan") && clean.contains("name") { tempMapping["plan_name"] = i }
                else if clean.contains("plan") && clean.contains("type") { tempMapping["plan_type"] = i }
                else if clean.contains("consolidated") && clean.contains("premium") { tempMapping["monthly_premium"] = i }
                else if clean.contains("deductible") { tempMapping["deductible"] = i }
                else if clean == "snp type" { tempMapping["snp_type"] = i }
            }
            if foundKeyColumn && tempMapping["contract_id"] != nil { return (tempMapping, rowIndex) }
        }
        return ([:], 0)
    }

    private func fastBareMetalStream(url: URL, table: String, mapping: [String: Int], filterEnrollment: Bool, skipRows: Int) throws {
        let cols: [String] = table == "staging_enrollment" 
            ? ["contract_id", "plan_id", "state", "county", "enrollment"]
            : (table == "staging_contracts" 
                ? ["contract_id", "plan_id", "organization_type", "plan_type", "offers_part_d", "organization_name", "organization_marketing_name", "plan_name", "parent_organization", "contract_effective_date", "is_snp", "is_egwp"]
                : ["contract_id", "plan_id", "carrier_name", "plan_name", "plan_type", "monthly_premium", "deductible", "snp_type"])

        let colIndices = cols.map { mapping[$0] ?? -1 }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let sql = "INSERT INTO \(table) (\(cols.joined(separator: ","))) VALUES (\(cols.map { _ in "?" }.joined(separator: ",")))"
        let stmt = try store.database.prepare(sql: sql)
        defer { sqlite3_finalize(stmt) }
        
        try store.database.execute(sql: "BEGIN TRANSACTION;")
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let ptr = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let size = bytes.count
            var lineStart = 0; var rowCount = 0; var currentLineIndex = 0
            var fieldOffsets = [(start: Int, len: Int)](repeating: (0, 0), count: 64)
            while lineStart < size {
                let remaining = size - lineStart
                let newline = memchr(ptr.advanced(by: lineStart), 10, remaining)
                let rawLineEnd = newline.map { ptr.distance(to: $0.assumingMemoryBound(to: UInt8.self)) } ?? size
                let nextLineStart = newline == nil ? size : rawLineEnd + 1
                let lineEnd = rawLineEnd > lineStart && ptr[rawLineEnd - 1] == 13 ? rawLineEnd - 1 : rawLineEnd
                if lineEnd > lineStart {
                    if currentLineIndex >= skipRows {
                        let skipped = filterEnrollment && isSuppressedEnrollment(ptr: ptr, s: lineStart, e: lineEnd)
                        if !skipped {
                            let fCount = parseFieldsFast(ptr: ptr, s: lineStart, e: lineEnd, offsets: &fieldOffsets)
                            _ = sqlite3_reset(stmt)
                            for (targetIdx, csvIdx) in colIndices.enumerated() {
                                if csvIdx >= 0 && csvIdx < fCount {
                                    let off = fieldOffsets[csvIdx]
                                    if off.len > 0 {
                                        let fieldPtr = ptr.advanced(by: off.start)
                                        _ = fieldPtr.withMemoryRebound(to: Int8.self, capacity: off.len) { int8Ptr in
                                            sqlite3_bind_text(stmt, Int32(targetIdx + 1), int8Ptr, Int32(off.len), SQLITE_STATIC_PTR)
                                        }
                                    } else { _ = sqlite3_bind_null(stmt, Int32(targetIdx + 1)) }
                                } else { _ = sqlite3_bind_null(stmt, Int32(targetIdx + 1)) }
                            }
                            _ = sqlite3_step(stmt)
                            rowCount += 1
                        }
                    }
                    currentLineIndex += 1
                }
                lineStart = nextLineStart
            }
            print("DEBUG: \(table) Ingested \(rowCount) rows")
        }
        try store.database.execute(sql: "COMMIT;")
    }

    private func isSuppressedEnrollment(ptr: UnsafePointer<UInt8>, s: Int, e: Int) -> Bool {
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
            else if c.contains("snp") { mapping["is_snp"] = i }
            else if c.contains("eghp") || c.contains("employer") { mapping["is_egwp"] = i }
            else if c.contains("organization") && cleanHeader(c).contains("marketing") { mapping["organization_marketing_name"] = i }
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
}

extension SQLiteDatabase {
    var dbPointer: OpaquePointer? { return Mirror(reflecting: self).descendant("db") as? OpaquePointer }
}
