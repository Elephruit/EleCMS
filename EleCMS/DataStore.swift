import Foundation

final class DataStore {
    let baseDirectory: URL
    let recentURL: URL
    let yearURLs: [Int: URL]

    init(baseDirectory: URL, years: [Int]) {
        self.baseDirectory = baseDirectory

        // URL for recent database
        self.recentURL = baseDirectory.appendingPathComponent("recent.db")

        // URLs for each year database
        var urls = [Int: URL]()
        for year in years {
            let url = baseDirectory.appendingPathComponent("\(year).db")
            urls[year] = url
        }
        self.yearURLs = urls
    }

    func prepareStores() {
        initializeRecent()
        for year in yearURLs.keys.sorted() {
            initializeYear(year: year)
        }
    }

    func initializeYear(year: Int) {
        guard let url = yearURLs[year] else {
            print("No URL found for year \(year)")
            return
        }
        let db = DatabaseFactory.openDatabase(at: url)

        applyPragmas(to: db)

        print("Initializing year database for \(year) at \(url.path)")

        for statement in DBSchema.yearStatements {
            print("Executing SQL on year database \(year): \(statement)")
            // TODO: Execute statement in a GRDB transaction
        }
    }

    func initializeRecent() {
        let db = DatabaseFactory.openDatabase(at: recentURL)

        applyPragmas(to: db)

        print("Initializing recent database at \(recentURL.path)")

        for statement in DBSchema.recentStatements {
            print("Executing SQL on recent database: \(statement)")
            // TODO: Execute statement in a GRDB transaction
        }
    }

    private func applyPragmas(to db: Database) {
        for pragma in DBSchema.pragmas {
            print("Applying PRAGMA: \(pragma)")
            // TODO: Execute pragma on the database
        }
    }

    func attach(years: [Int]) {
        print("Attaching year databases:")
        for year in years {
            if let url = yearURLs[year] {
                print("Would attach database for year \(year) at \(url.path)")
                // TODO: Implement actual attach logic using GRDB
            } else {
                print("No database found to attach for year \(year)")
            }
        }
    }
}

// Dummy placeholders to make the file self-contained and compilable

struct DBSchema {
    static let pragmas = [
        "PRAGMA foreign_keys = ON",
        "PRAGMA journal_mode = WAL"
    ]

    static let yearStatements = [
        "CREATE TABLE IF NOT EXISTS year_data (id INTEGER PRIMARY KEY, value TEXT);"
    ]

    static let recentStatements = [
        "CREATE TABLE IF NOT EXISTS recent_data (id INTEGER PRIMARY KEY, value TEXT);"
    ]
}

class Database {
    // Dummy database class
}

class DatabaseFactory {
    static func openDatabase(at url: URL) -> Database {
        print("Opening database at \(url.path)")
        return Database()
    }
}
