import Foundation

struct Logger {
    static func log(_ message: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        print("[\(df.string(from: Date()))] \(message)")
    }
}
