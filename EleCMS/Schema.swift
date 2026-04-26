import Foundation

struct DBSchema {
    static let pragmas: String = """
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA temp_store = MEMORY;
    PRAGMA cache_size = -200000;
    PRAGMA foreign_keys = ON;
    """

    static let createTables: String = """
    -- Staging tables for CPSC data
    CREATE TABLE IF NOT EXISTS staging_enrollment (
        contract_id TEXT,
        plan_id TEXT,
        state TEXT,
        county TEXT,
        enrollment TEXT
    );

    CREATE TABLE IF NOT EXISTS staging_contracts (
        contract_id TEXT,
        plan_id TEXT,
        organization_type TEXT,
        plan_type TEXT,
        offers_part_d TEXT,
        organization_name TEXT,
        organization_marketing_name TEXT,
        plan_name TEXT,
        parent_organization TEXT,
        contract_effective_date TEXT
    );

    -- Staging table for Landscape data
    CREATE TABLE IF NOT EXISTS staging_landscape (
        contract_id TEXT,
        plan_id TEXT,
        carrier_name TEXT,
        plan_name TEXT,
        plan_type TEXT,
        monthly_premium REAL,
        deductible REAL
    );

    -- Final Dimensions
    CREATE TABLE IF NOT EXISTS carrier_dim (
        carrier_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
    );

    CREATE TABLE IF NOT EXISTS plan_dim (
        plan_id INTEGER PRIMARY KEY AUTOINCREMENT,
        cms_plan_id TEXT NOT NULL,
        contract_id TEXT NOT NULL,
        name TEXT,
        type TEXT,
        carrier_id INTEGER,
        FOREIGN KEY (carrier_id) REFERENCES carrier_dim(carrier_id),
        UNIQUE(cms_plan_id, contract_id)
    );

    CREATE TABLE IF NOT EXISTS county_dim (
        county_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        state TEXT NOT NULL,
        UNIQUE(name, state)
    );

    -- Fact Table
    CREATE TABLE IF NOT EXISTS enrollment_records (
        plan_id INTEGER NOT NULL,
        county_id INTEGER NOT NULL,
        period_id INTEGER NOT NULL,
        enrollment INTEGER NOT NULL,
        PRIMARY KEY (plan_id, county_id, period_id),
        FOREIGN KEY (plan_id) REFERENCES plan_dim(plan_id),
        FOREIGN KEY (county_id) REFERENCES county_dim(county_id)
    ) WITHOUT ROWID;

    CREATE TABLE IF NOT EXISTS periods (
        period_id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        UNIQUE(year, month)
    );
    """

    static let mergeStagingToFinal: String = """
    -- Insert new carriers
    INSERT OR IGNORE INTO carrier_dim (name)
    SELECT DISTINCT COALESCE(organization_marketing_name, organization_name) 
    FROM staging_contracts 
    WHERE organization_name IS NOT NULL;

    -- Insert new counties
    INSERT OR IGNORE INTO county_dim (name, state)
    SELECT DISTINCT county, state FROM staging_enrollment;

    -- Insert new plans
    INSERT OR IGNORE INTO plan_dim (cms_plan_id, contract_id, name, type, carrier_id)
    SELECT 
        sc.plan_id, 
        sc.contract_id, 
        sc.plan_name, 
        sc.plan_type,
        c.carrier_id
    FROM staging_contracts sc
    LEFT JOIN carrier_dim c ON c.name = COALESCE(sc.organization_marketing_name, sc.organization_name);

    -- Insert enrollment records (filtering out '*' happens during ingestion or here)
    INSERT OR REPLACE INTO enrollment_records (plan_id, county_id, period_id, enrollment)
    SELECT 
        p.plan_id,
        co.county_id,
        :period_id,
        CAST(REPLACE(se.enrollment, ',', '') AS INTEGER)
    FROM staging_enrollment se
    JOIN plan_dim p ON p.cms_plan_id = se.plan_id AND p.contract_id = se.contract_id
    JOIN county_dim co ON co.name = se.county AND co.state = se.state
    WHERE se.enrollment NOT LIKE '*%' 
      AND se.enrollment IS NOT NULL 
      AND se.enrollment != '';
    """

    static let momSQLExample: String = """
    SELECT
        plan_id,
        county_id,
        period_id,
        enrollment - LAG(enrollment) OVER w AS absolute_growth,
        CASE
            WHEN LAG(enrollment) OVER w IS NULL OR LAG(enrollment) OVER w = 0 THEN 0
            ELSE CAST(enrollment - LAG(enrollment) OVER w AS REAL) / LAG(enrollment) OVER w
        END AS percentage_growth
    FROM enrollment_records
    WINDOW w AS (PARTITION BY plan_id, county_id ORDER BY period_id);
    """

    static let yoySQLExample: String = """
    SELECT
        e.plan_id,
        e.county_id,
        e.period_id,
        e.enrollment - e12.enrollment AS absolute_growth,
        CASE
            WHEN e12.enrollment IS NULL OR e12.enrollment = 0 THEN 0
            ELSE CAST(e.enrollment - e12.enrollment AS REAL) / e12.enrollment
        END AS percentage_growth
    FROM enrollment_records e
    LEFT JOIN enrollment_records e12
        ON e.plan_id = e12.plan_id
        AND e.county_id = e12.county_id
        AND e.period_id = e12.period_id + 12;
    """
}
