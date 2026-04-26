import Foundation

final class DataStore {
    let baseDirectory: URL
    let database: SQLiteDatabase

    init(directory: URL) throws {
        self.baseDirectory = directory
        let dbURL = directory.appendingPathComponent("EleCMS.sqlite")
        self.database = try EleDatabaseFactory.makeDatabase(at: dbURL)
    }
    
    func getPeriodID(year: Int, month: Int) throws -> Int {
        let results = try database.query(sql: "SELECT period_id FROM periods WHERE year = ? AND month = ?", arguments: [year, month])
        if let first = results.first, let periodID = first["period_id"] as? Int {
            return periodID
        }
        
        try database.execute(sql: "INSERT OR IGNORE INTO periods (year, month) VALUES (\(year), \(month))")
        return Int(database.lastInsertedRowID)
    }
}
