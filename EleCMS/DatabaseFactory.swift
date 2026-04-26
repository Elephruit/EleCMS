import Foundation

final class EleDatabaseFactory {
    static func makeDatabase(at url: URL) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: url.path)
        try db.execute(sql: DBSchema.pragmas)
        try db.execute(sql: DBSchema.createTables)
        
        // Simple migration: Add columns to plan_dim if they don't exist
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN is_snp INTEGER DEFAULT 0;")
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN is_egwp INTEGER DEFAULT 0;")
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN snp_type TEXT;")
        
        return db
    }
}
