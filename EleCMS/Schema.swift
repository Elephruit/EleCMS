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
        ssa_county_code TEXT,
        fips_county_code TEXT,
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
        contract_effective_date TEXT,
        is_snp TEXT,
        is_egwp TEXT
    );

    -- Staging table for Landscape data
    CREATE TABLE IF NOT EXISTS staging_landscape (
        contract_id TEXT,
        plan_id TEXT,
        state TEXT,
        county TEXT,
        carrier_name TEXT,
        plan_name TEXT,
        plan_type TEXT,
        monthly_premium TEXT,
        deductible TEXT,
        snp_type TEXT
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
        is_snp INTEGER DEFAULT 0,
        is_egwp INTEGER DEFAULT 0,
        snp_type TEXT,
        FOREIGN KEY (carrier_id) REFERENCES carrier_dim(carrier_id),
        UNIQUE(cms_plan_id, contract_id)
    );

    CREATE TABLE IF NOT EXISTS county_dim (
        county_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        state TEXT NOT NULL,
        ssa_county_code TEXT NOT NULL DEFAULT '',
        fips_county_code TEXT NOT NULL DEFAULT '',
        UNIQUE(name, state, ssa_county_code, fips_county_code)
    );

    -- Fact Tables
    CREATE TABLE IF NOT EXISTS enrollment_records (
        plan_id INTEGER NOT NULL,
        county_id INTEGER NOT NULL,
        period_id INTEGER NOT NULL,
        enrollment INTEGER NOT NULL,
        PRIMARY KEY (plan_id, county_id, period_id),
        FOREIGN KEY (plan_id) REFERENCES plan_dim(plan_id),
        FOREIGN KEY (county_id) REFERENCES county_dim(county_id)
    ) WITHOUT ROWID;

    CREATE TABLE IF NOT EXISTS landscape_records (
        plan_id INTEGER NOT NULL,
        year INTEGER NOT NULL,
        monthly_premium REAL,
        deductible REAL,
        PRIMARY KEY (plan_id, year),
        FOREIGN KEY (plan_id) REFERENCES plan_dim(plan_id)
    ) WITHOUT ROWID;

    -- Map table for service areas (from landscape)
    CREATE TABLE IF NOT EXISTS plan_service_area (
        plan_id INTEGER NOT NULL,
        county_id INTEGER NOT NULL,
        year INTEGER NOT NULL,
        PRIMARY KEY (plan_id, county_id, year),
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
    -- 1. Sync Carriers (Consolidate into Parent Organization)
    INSERT OR IGNORE INTO carrier_dim (name)
    SELECT DISTINCT TRIM(parent_organization)
    FROM staging_contracts 
    WHERE parent_organization IS NOT NULL AND parent_organization != '';

    -- 2. Sync Counties
    INSERT OR IGNORE INTO county_dim (name, state, ssa_county_code, fips_county_code)
    SELECT DISTINCT
        COALESCE(county, ''),
        COALESCE(state, ''),
        COALESCE(ssa_county_code, ''),
        COALESCE(fips_county_code, '')
    FROM staging_enrollment;

    -- 3. Sync Plans from both files
    INSERT OR IGNORE INTO plan_dim (cms_plan_id, contract_id)
    SELECT DISTINCT plan_id, contract_id FROM staging_contracts;

    INSERT OR IGNORE INTO plan_dim (cms_plan_id, contract_id)
    SELECT DISTINCT plan_id, contract_id FROM staging_enrollment;

    -- 4. Update Plans with details and strict Parent-Org Carrier Mapping
    UPDATE plan_dim
    SET 
        name = (SELECT sc.plan_name FROM staging_contracts sc WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id),
        type = (SELECT sc.plan_type FROM staging_contracts sc WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id),
        carrier_id = (
            SELECT c.carrier_id 
            FROM staging_contracts sc 
            JOIN carrier_dim c ON c.name = TRIM(sc.parent_organization)
            WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id
        ),
        is_snp = (
            SELECT CASE WHEN sc.is_snp = 'Yes' OR sc.offers_part_d LIKE '%SNP%' OR sc.organization_type LIKE '%SNP%' THEN 1 ELSE 0 END
            FROM staging_contracts sc WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id
        ),
        is_egwp = (
            SELECT CASE WHEN sc.is_egwp = 'Yes' OR sc.parent_organization LIKE '%EGHP%' OR sc.organization_name LIKE '%EGHP%' THEN 1 ELSE 0 END
            FROM staging_contracts sc WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id
        )
    WHERE EXISTS (SELECT 1 FROM staging_contracts sc WHERE sc.plan_id = plan_dim.cms_plan_id AND sc.contract_id = plan_dim.contract_id);

    -- 5. Insert enrollment records
    INSERT OR REPLACE INTO enrollment_records (plan_id, county_id, period_id, enrollment)
    SELECT 
        p.plan_id,
        co.county_id,
        :period_id,
        CAST(REPLACE(se.enrollment, ',', '') AS INTEGER)
    FROM staging_enrollment se
    JOIN plan_dim p ON p.cms_plan_id = se.plan_id AND p.contract_id = se.contract_id
    JOIN county_dim co
        ON co.name = COALESCE(se.county, '')
        AND co.state = COALESCE(se.state, '')
        AND co.ssa_county_code = COALESCE(se.ssa_county_code, '')
        AND co.fips_county_code = COALESCE(se.fips_county_code, '')
    WHERE se.enrollment NOT LIKE '*%' 
      AND se.enrollment IS NOT NULL 
      AND se.enrollment != '';
    """

    static let mergeLandscapeToFinal: String = """
    -- 1. Sync Counties from Landscape (In case they weren't in enrollment)
    INSERT OR IGNORE INTO county_dim (name, state)
    SELECT DISTINCT county, state FROM staging_landscape WHERE county IS NOT NULL AND state IS NOT NULL;

    -- 2. Sync Plans from Landscape
    INSERT OR IGNORE INTO plan_dim (cms_plan_id, contract_id)
    SELECT DISTINCT plan_id, contract_id FROM staging_landscape;

    -- 3. Update snp_type for plans from landscape data
    UPDATE plan_dim SET
        snp_type = (SELECT sl.snp_type FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id),
        is_snp = 1
    WHERE EXISTS (SELECT 1 FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id AND sl.snp_type IS NOT NULL AND sl.snp_type != '');

    -- 4. Insert landscape records (Premiums/Deductibles)
    INSERT OR REPLACE INTO landscape_records (plan_id, year, monthly_premium, deductible)
    SELECT 
        p.plan_id,
        :year,
        CAST(REPLACE(REPLACE(sl.monthly_premium, '$', ''), ',', '') AS REAL),
        CAST(REPLACE(REPLACE(sl.deductible, '$', ''), ',', '') AS REAL)
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id;

    -- 5. Map Service Area (Counties offered)
    INSERT OR IGNORE INTO plan_service_area (plan_id, county_id, year)
    SELECT DISTINCT p.plan_id, co.county_id, :year
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id
    JOIN county_dim co ON co.name = sl.county AND co.state = sl.state;
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
