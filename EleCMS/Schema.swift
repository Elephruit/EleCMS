import Foundation

struct DBSchema {
    // Pragmas for yearly database
    static let yearlyPragmas = """
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    """

    // Tables for yearly database
    static let yearlyTables = """
    -- Dimensions Tables
    CREATE TABLE IF NOT EXISTS plan_dim (
        plan_id TEXT PRIMARY KEY,
        plan_name TEXT NOT NULL,
        plan_type TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS county_dim (
        county_id INTEGER PRIMARY KEY,
        county_name TEXT NOT NULL,
        state TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS contract_dim (
        contract_id TEXT PRIMARY KEY,
        contract_name TEXT NOT NULL
    );

    -- Enrollment Records Table WITHOUT ROWID for yearly database
    CREATE TABLE IF NOT EXISTS enrollment_records (
        record_id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        county_id INTEGER NOT NULL,
        contract_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        enrollment_count INTEGER NOT NULL,
        FOREIGN KEY(plan_id) REFERENCES plan_dim(plan_id),
        FOREIGN KEY(county_id) REFERENCES county_dim(county_id),
        FOREIGN KEY(contract_id) REFERENCES contract_dim(contract_id)
    ) WITHOUT ROWID;

    -- Growth Metrics Table
    CREATE TABLE IF NOT EXISTS growth_metrics (
        metric_id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id TEXT NOT NULL,
        county_id INTEGER NOT NULL,
        year INTEGER NOT NULL,
        enrollment_growth REAL NOT NULL,
        FOREIGN KEY(plan_id) REFERENCES plan_dim(plan_id),
        FOREIGN KEY(county_id) REFERENCES county_dim(county_id)
    );

    -- Periods Table
    CREATE TABLE IF NOT EXISTS periods (
        period_id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        description TEXT
    );
    """

    // Tables for recent database
    static let recentTables = """
    -- Dimensions Tables
    CREATE TABLE IF NOT EXISTS plan_dim (
        plan_id TEXT PRIMARY KEY,
        plan_name TEXT NOT NULL,
        plan_type TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS county_dim (
        county_id INTEGER PRIMARY KEY,
        county_name TEXT NOT NULL,
        state TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS contract_dim (
        contract_id TEXT PRIMARY KEY,
        contract_name TEXT NOT NULL
    );

    -- Enrollment Records Table WITHOUT ROWID for recent database
    CREATE TABLE IF NOT EXISTS enrollment_records (
        record_id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        county_id INTEGER NOT NULL,
        contract_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        enrollment_count INTEGER NOT NULL,
        FOREIGN KEY(plan_id) REFERENCES plan_dim(plan_id),
        FOREIGN KEY(county_id) REFERENCES county_dim(county_id),
        FOREIGN KEY(contract_id) REFERENCES contract_dim(contract_id)
    ) WITHOUT ROWID;
    """

    // FTS5 virtual table setup for plan search (requires SQLite compiled with FTS5 support)
    static let ftsSetup = """
    -- FTS5 virtual table for plan search
    -- Note: Ensure SQLite is compiled with FTS5 enabled.
    CREATE VIRTUAL TABLE IF NOT EXISTS plan_search USING fts5(plan_name, plan_type, content='plan_dim', content_rowid='plan_id');
    """

    // Materialized indexes to optimize queries
    static let materializedIndexes = """
    CREATE INDEX IF NOT EXISTS idx_enrollment_plan_year ON enrollment_records(plan_id, year);
    CREATE INDEX IF NOT EXISTS idx_enrollment_county_year ON enrollment_records(county_id, year);
    CREATE INDEX IF NOT EXISTS idx_growth_plan_county_year ON growth_metrics(plan_id, county_id, year);
    """
}
