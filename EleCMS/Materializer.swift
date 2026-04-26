import Foundation

final class Materializer {
    let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func materializeMoM(forYear year: Int) throws {
        print("-- MoM SQL --\n\(DBSchema.momSQLExample)")
    }

    func refreshRecentCache(lastMonths: Int = 24) throws {
        print("-- Refreshing recent cache for last \(lastMonths) months")
    }

    func materializeYoY(crossYears years: [Int]) throws {
        print("-- YoY materialization across years: \(years)")
        print(DBSchema.yoySQLExample)
    }
}
