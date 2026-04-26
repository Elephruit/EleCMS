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

struct CarrierTrendPoint: Identifiable {
    var id: String { "\(carrier)-\(year)-\(month)" }
    let carrier: String
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

enum MarketSegment: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case total = "Market"
    case snp = "SNP"
    case egwpNonPDP = "EGWP (non-PDP)"
    case individualNonSNP = "Individual non-SNP"
    case pdpGroup = "PDP Group"
    case pdpIndividual = "PDP Individual"
    
    var sqlFilter: String {
        switch self {
        case .total: return ""
        case .snp: return " AND p.is_snp = 1"
        case .egwpNonPDP: return " AND p.is_egwp = 1 AND p.type NOT IN ('Medicare Prescription Drug Plan', 'Employer/Union Only Direct Contract PDP')"
        case .individualNonSNP: return " AND p.is_egwp = 0 AND p.is_snp = 0 AND p.type NOT IN ('Medicare Prescription Drug Plan', 'Medicare-Medicaid Plan HMO/HMOPOS', 'Employer/Union only direct contract pdp')"
        case .pdpGroup: return " AND p.is_egwp = 1 AND p.type IN ('Employer/Union only direct contract pdp', 'Medicare Prescription Drug Plan')"
        case .pdpIndividual: return " AND p.is_egwp = 0 AND p.type = 'Medicare Prescription Drug Plan'"
        }
    }
}
