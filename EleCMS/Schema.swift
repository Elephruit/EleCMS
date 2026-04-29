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
        part_d_deductible TEXT,
        part_c_premium TEXT,
        part_d_basic_premium TEXT,
        part_d_supplemental_premium TEXT,
        part_d_total_premium TEXT,
        low_income_premium_subsidy TEXT,
        part_d_lips_amount TEXT,
        part_d_low_income_premium TEXT,
        oop_threshold TEXT,
        moop_amount TEXT,
        part_d_coverage TEXT,
        drug_benefit_category TEXT,
        drug_benefit_type TEXT,
        zero_dollar_cost_sharing TEXT,
        no_part_d_deductible TEXT,
        part_c_star_rating TEXT,
        part_d_star_rating TEXT,
        overall_star_rating TEXT,
        snp_type TEXT,
        ssa_county_code TEXT,
        fips_county_code TEXT
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
        part_d_deductible REAL,
        part_c_premium REAL,
        part_d_basic_premium REAL,
        part_d_supplemental_premium REAL,
        part_d_total_premium REAL,
        low_income_premium_subsidy REAL,
        part_d_lips_amount REAL,
        part_d_low_income_premium REAL,
        oop_threshold REAL,
        moop_amount REAL,
        part_d_coverage TEXT,
        drug_benefit_category TEXT,
        drug_benefit_type TEXT,
        zero_dollar_cost_sharing TEXT,
        no_part_d_deductible TEXT,
        part_c_star_rating REAL,
        part_d_star_rating REAL,
        overall_star_rating REAL,
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

    static let createIndexes: String = """
    CREATE INDEX IF NOT EXISTS idx_county_fips ON county_dim(fips_county_code) WHERE fips_county_code != '';
    CREATE INDEX IF NOT EXISTS idx_county_ssa ON county_dim(ssa_county_code) WHERE ssa_county_code != '';
    CREATE INDEX IF NOT EXISTS idx_county_name_state_nocase ON county_dim(name COLLATE NOCASE, state COLLATE NOCASE);
    CREATE INDEX IF NOT EXISTS idx_plan_service_area_plan_year ON plan_service_area(plan_id, year);
    CREATE INDEX IF NOT EXISTS idx_landscape_records_year_plan ON landscape_records(year, plan_id);
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
    INSERT OR IGNORE INTO county_dim (name, state, ssa_county_code, fips_county_code)
    SELECT DISTINCT
        COALESCE(county, ''),
        COALESCE(state, ''),
        COALESCE(ssa_county_code, ''),
        COALESCE(fips_county_code, '')
    FROM staging_landscape
    WHERE county IS NOT NULL AND state IS NOT NULL;

    -- 2. Sync Plans from Landscape
    INSERT OR IGNORE INTO plan_dim (cms_plan_id, contract_id)
    SELECT DISTINCT plan_id, contract_id FROM staging_landscape;

    -- 3. Update plan details (type, snp_type) from landscape data
    UPDATE plan_dim SET
        snp_type = (SELECT sl.snp_type FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id LIMIT 1),
        type = (SELECT sl.plan_type FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id LIMIT 1),
        is_snp = (SELECT CASE WHEN sl.snp_type IS NOT NULL AND sl.snp_type != '' THEN 1 ELSE 0 END FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id LIMIT 1)
    WHERE EXISTS (SELECT 1 FROM staging_landscape sl WHERE sl.plan_id = plan_dim.cms_plan_id AND sl.contract_id = plan_dim.contract_id);

    -- 4. Insert landscape records (Premiums/Deductibles)
    INSERT OR REPLACE INTO landscape_records (
        plan_id,
        year,
        monthly_premium,
        deductible,
        part_d_deductible,
        part_c_premium,
        part_d_basic_premium,
        part_d_supplemental_premium,
        part_d_total_premium,
        low_income_premium_subsidy,
        part_d_lips_amount,
        part_d_low_income_premium,
        oop_threshold,
        moop_amount,
        part_d_coverage,
        drug_benefit_category,
        drug_benefit_type,
        zero_dollar_cost_sharing,
        no_part_d_deductible,
        part_c_star_rating,
        part_d_star_rating,
        overall_star_rating
    )
    SELECT 
        p.plan_id,
        :year,
        MAX(CASE WHEN sl.monthly_premium IS NULL OR TRIM(sl.monthly_premium) = '' OR sl.monthly_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.monthly_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.monthly_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.monthly_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.deductible IS NULL OR TRIM(sl.deductible) = '' OR sl.deductible LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.deductible) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.deductible), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.deductible), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_deductible IS NULL OR TRIM(sl.part_d_deductible) = '' OR sl.part_d_deductible LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_deductible) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_deductible), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_deductible), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_c_premium IS NULL OR TRIM(sl.part_c_premium) = '' OR sl.part_c_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_c_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_c_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_c_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_basic_premium IS NULL OR TRIM(sl.part_d_basic_premium) = '' OR sl.part_d_basic_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_basic_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_basic_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_basic_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_supplemental_premium IS NULL OR TRIM(sl.part_d_supplemental_premium) = '' OR sl.part_d_supplemental_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_supplemental_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_supplemental_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_supplemental_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_total_premium IS NULL OR TRIM(sl.part_d_total_premium) = '' OR sl.part_d_total_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_total_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_total_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_total_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.low_income_premium_subsidy IS NULL OR TRIM(sl.low_income_premium_subsidy) = '' OR sl.low_income_premium_subsidy LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.low_income_premium_subsidy) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.low_income_premium_subsidy), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.low_income_premium_subsidy), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_lips_amount IS NULL OR TRIM(sl.part_d_lips_amount) = '' OR sl.part_d_lips_amount LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_lips_amount) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_lips_amount), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_lips_amount), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.part_d_low_income_premium IS NULL OR TRIM(sl.part_d_low_income_premium) = '' OR sl.part_d_low_income_premium LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.part_d_low_income_premium) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.part_d_low_income_premium), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.part_d_low_income_premium), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.oop_threshold IS NULL OR TRIM(sl.oop_threshold) = '' OR sl.oop_threshold LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.oop_threshold) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.oop_threshold), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.oop_threshold), '$', ''), ',', '') AS REAL) END),
        MAX(CASE WHEN sl.moop_amount IS NULL OR TRIM(sl.moop_amount) = '' OR sl.moop_amount LIKE '%Applicable%' THEN NULL WHEN TRIM(sl.moop_amount) LIKE '(%' THEN -CAST(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(sl.moop_amount), '$', ''), ',', ''), '(', ''), ')', '') AS REAL) ELSE CAST(REPLACE(REPLACE(TRIM(sl.moop_amount), '$', ''), ',', '') AS REAL) END),
        MAX(NULLIF(TRIM(sl.part_d_coverage), '')),
        MAX(NULLIF(TRIM(sl.drug_benefit_category), '')),
        MAX(NULLIF(TRIM(sl.drug_benefit_type), '')),
        MAX(NULLIF(TRIM(sl.zero_dollar_cost_sharing), '')),
        MAX(NULLIF(TRIM(sl.no_part_d_deductible), '')),
        MAX(CASE WHEN sl.part_c_star_rating IS NULL OR TRIM(sl.part_c_star_rating) = '' OR sl.part_c_star_rating LIKE '%Applicable%' THEN NULL ELSE CAST(TRIM(sl.part_c_star_rating) AS REAL) END),
        MAX(CASE WHEN sl.part_d_star_rating IS NULL OR TRIM(sl.part_d_star_rating) = '' OR sl.part_d_star_rating LIKE '%Applicable%' THEN NULL ELSE CAST(TRIM(sl.part_d_star_rating) AS REAL) END),
        MAX(CASE WHEN sl.overall_star_rating IS NULL OR TRIM(sl.overall_star_rating) = '' OR sl.overall_star_rating LIKE '%Applicable%' THEN NULL ELSE CAST(TRIM(sl.overall_star_rating) AS REAL) END)
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id
    GROUP BY p.plan_id;

    -- 5. Map Service Area (Counties offered)
    -- Multi-pass merge to keep it fast (Index-friendly)

    -- Pass 1: FIPS Match (Highest accuracy)
    INSERT OR IGNORE INTO plan_service_area (plan_id, county_id, year)
    SELECT DISTINCT p.plan_id, co.county_id, :year
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id
    JOIN county_dim co ON co.fips_county_code = sl.fips_county_code
    WHERE sl.fips_county_code != '';

    -- Pass 2: SSA Match
    INSERT OR IGNORE INTO plan_service_area (plan_id, county_id, year)
    SELECT DISTINCT p.plan_id, co.county_id, :year
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id
    JOIN county_dim co ON co.ssa_county_code = sl.ssa_county_code
    WHERE sl.ssa_county_code != '';

    -- Pass 3: Name/State Match (Fallback)
    INSERT OR IGNORE INTO plan_service_area (plan_id, county_id, year)
    SELECT DISTINCT p.plan_id, co.county_id, :year
    FROM staging_landscape sl
    JOIN plan_dim p ON p.cms_plan_id = sl.plan_id AND p.contract_id = sl.contract_id
    JOIN county_dim co
        ON co.name = sl.county COLLATE NOCASE
        AND co.state = sl.state COLLATE NOCASE;
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
