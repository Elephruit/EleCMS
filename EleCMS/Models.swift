import Foundation

struct EnrollmentByCountyByPlan: Identifiable {
    var id: String { "\(county)-\(plan)" }
    let county: String
    let plan: String
    let enrollment: Int
}

struct EnrollmentByCarrier: Identifiable {
    var id: String { carrier }
    let carrier: String
    let enrollment: Int
}

struct TrendPoint: Identifiable {
    var id: String { "\(year)-\(month)" }
    let year: Int
    let month: Int
    let enrollment: Int
    var date: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        return Calendar.current.date(from: components) ?? Date()
    }
}

struct Period: Identifiable, Hashable {
    let id: Int
    let year: Int
    let month: Int
    
    var name: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let monthName = formatter.monthSymbols[month - 1]
        return "\(monthName) \(year)"
    }
    
    var shortName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let monthName = formatter.shortMonthSymbols[month - 1]
        return "\(monthName) '\(year % 100)"
    }
}

struct DashboardFilter: Equatable {
    var state: String?
    var planType: String?
    var snp: String = "All" // "All", "Yes", "No"
    var egwp: String = "All" // "All", "Yes", "No"
    var dsnp: Bool = false
    var csnp: Bool = false
    var isnp: Bool = false
}
