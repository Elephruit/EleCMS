import Foundation

final class Materializer {
    private let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func materializeMoM(forYear year: Int) {
        let sql = """
        -- Materialize Month-over-Month (MoM) data for year \(year)
        WITH monthly_data AS (
            SELECT
                year,
                month,
                value,
                LAG(value) OVER (PARTITION BY year ORDER BY month) AS previous_month_value
            FROM \(DBSchema.tableName)
            WHERE year = \(year)
        )
        SELECT
            year,
            month,
            value,
            previous_month_value,
            (value - previous_month_value) AS mom_change
        FROM monthly_data;
        """
        print("Executing MoM materialization SQL for year \(year):\n\(sql)")
        // TODO: Execute the above SQL query via GRDB to materialize MoM data
    }

    func materializeYoY(crossYears years: [Int]) {
        let yearsList = years.map { String($0) }.joined(separator: ", ")
        let sql = """
        -- Materialize Year-over-Year (YoY) data for years [\(yearsList)]
        WITH yearly_data AS (
            SELECT
                year,
                month,
                value,
                LAG(value) OVER (PARTITION BY month ORDER BY year) AS previous_year_value
            FROM \(DBSchema.tableName)
            WHERE year IN (\(yearsList))
        )
        SELECT
            year,
            month,
            value,
            previous_year_value,
            (value - previous_year_value) AS yoy_change
        FROM yearly_data;
        """
        print("Executing YoY materialization SQL for years [\(yearsList)]:\n\(sql)")
        // TODO: Execute the above SQL query via GRDB to materialize YoY data
    }

    func refreshRecentCache(lastMonths: Int = 24) {
        print("""
        Refreshing recent cache for the last \(lastMonths) months:
        1. ATTACH recent.sqlite as 'recent'.
        2. ATTACH year databases as necessary.
        3. Perform UNION of data from year DBs filtered for the last \(lastMonths) months.
        4. Populate 'recent' database with the unioned data.
        5. DETACH year DBs and 'recent' after completion.
        """)
        // TODO: Implement the ATTACH, UNION, and cache population logic via GRDB
    }
}
