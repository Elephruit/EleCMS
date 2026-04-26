import Foundation

final class EleDatabaseFactory {
    static func makeDatabase(at url: URL) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: url.path)
        try db.execute(sql: DBSchema.pragmas)
        try db.execute(sql: DBSchema.createTables)
        return db
    }
}
