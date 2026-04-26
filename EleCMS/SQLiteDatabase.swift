import Foundation
import SQLite3

enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case execFailed(String)
    case bindFailed(String)
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    
    init(path: String) throws {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.openFailed(msg)
        }
    }
    
    deinit {
        sqlite3_close_v2(db)
    }
    
    func execute(sql: String) throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = String(cString: errMsg!)
            sqlite3_free(errMsg)
            throw SQLiteError.execFailed(msg)
        }
    }
    
    func prepare(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(msg)
        }
        return statement
    }
    
    func query(sql: String, arguments: [Any] = []) throws -> [[String: Any]] {
        guard let stmt = try prepare(sql: sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        try bind(stmt: stmt, arguments: arguments)
        
        var results: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(stmt)
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)
                
                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = nil
                }
            }
            results.append(row)
        }
        return results
    }
    
    func bind(stmt: OpaquePointer, arguments: [Any]) throws {
        for (index, arg) in arguments.enumerated() {
            let idx = Int32(index + 1)
            let status: Int32
            if let intVal = arg as? Int {
                status = sqlite3_bind_int64(stmt, idx, Int64(intVal))
            } else if let doubleVal = arg as? Double {
                status = sqlite3_bind_double(stmt, idx, doubleVal)
            } else if let stringVal = arg as? String {
                status = sqlite3_bind_text(stmt, idx, (stringVal as NSString).utf8String, -1, nil)
            } else {
                status = sqlite3_bind_null(stmt, idx)
            }
            
            if status != SQLITE_OK {
                throw SQLiteError.bindFailed("Failed to bind argument at index \(idx)")
            }
        }
    }
    
    var lastInsertedRowID: Int64 {
        return sqlite3_last_insert_rowid(db)
    }
}
