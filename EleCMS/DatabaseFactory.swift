import Foundation

final class EleDatabaseFactory {
    static func makeDatabase(at url: URL) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: url.path)
        try db.execute(sql: DBSchema.pragmas)
        try db.execute(sql: DBSchema.createTables)
        try migrateCountyIdentityIfNeeded(db)
        try db.execute(sql: DBSchema.createIndexes)
        
        // Simple migration: Add columns to plan_dim if they don't exist
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN is_snp INTEGER DEFAULT 0;")
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN is_egwp INTEGER DEFAULT 0;")
        try? db.execute(sql: "ALTER TABLE plan_dim ADD COLUMN snp_type TEXT;")
        try migrateLandscapeDetailColumns(db)
        
        return db
    }

    private static func migrateLandscapeDetailColumns(_ db: SQLiteDatabase) throws {
        let realColumns = [
            "part_d_deductible", "part_c_premium", "part_d_basic_premium",
            "part_d_supplemental_premium", "part_d_total_premium",
            "low_income_premium_subsidy", "part_d_lips_amount",
            "part_d_low_income_premium", "oop_threshold", "moop_amount",
            "part_c_star_rating", "part_d_star_rating", "overall_star_rating"
        ]
        for column in realColumns {
            try? db.execute(sql: "ALTER TABLE landscape_records ADD COLUMN \(column) REAL;")
        }

        let textColumns = [
            "part_d_coverage", "drug_benefit_category", "drug_benefit_type",
            "zero_dollar_cost_sharing", "no_part_d_deductible"
        ]
        for column in textColumns {
            try? db.execute(sql: "ALTER TABLE landscape_records ADD COLUMN \(column) TEXT;")
        }
    }
    
    private static func migrateCountyIdentityIfNeeded(_ db: SQLiteDatabase) throws {
        let columns = try db.query(sql: "PRAGMA table_info(county_dim)")
            .compactMap { $0["name"] as? String }
        guard !columns.contains("ssa_county_code") || !columns.contains("fips_county_code") else {
            return
        }
        
        try db.execute(sql: """
            PRAGMA foreign_keys = OFF;
            DROP TABLE IF EXISTS county_dim_new;
            CREATE TABLE county_dim_new (
                county_id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                state TEXT NOT NULL,
                ssa_county_code TEXT NOT NULL DEFAULT '',
                fips_county_code TEXT NOT NULL DEFAULT '',
                UNIQUE(name, state, ssa_county_code, fips_county_code)
            );
            INSERT OR IGNORE INTO county_dim_new (county_id, name, state, ssa_county_code, fips_county_code)
            SELECT county_id, name, state, '', '' FROM county_dim;
            DROP TABLE county_dim;
            ALTER TABLE county_dim_new RENAME TO county_dim;
            PRAGMA foreign_keys = ON;
        """)
    }
}
