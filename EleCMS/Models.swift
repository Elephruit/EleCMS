import Foundation

enum NavDestination: Hashable {
    case marketOverview
    case geographicDeepDive
    case carrierDeepDive
    case planDeepDive(id: String? = nil)
    case dataCatalog
    case settings
}

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
        let monthName = DateFormatter().monthSymbols[month - 1]
        return "\(monthName) \(year)"
    }
    
    var shortName: String {
        let monthName = DateFormatter().shortMonthSymbols[month - 1]
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

struct StateHelper {
    static let map: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
        "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
        "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
        "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "DC": "District of Columbia", "PR": "Puerto Rico", "VI": "Virgin Islands", "GU": "Guam",
        "AS": "American Samoa", "MP": "Northern Mariana Islands"
    ]
    
    static func fullName(for abbrev: String) -> String {
        return map[abbrev.uppercased()] ?? abbrev
    }
}

// MARK: - Drill-down Models

struct GeographicBreakdown: Identifiable {
    let id: String // Carrier Name
    let enrollment: Int
    var types: [ProductTypeBreakdown] = []
}

struct ProductTypeBreakdown: Identifiable {
    let id: String // Type Name
    let enrollment: Int
    let momDiff: Int
    let momPct: Double
    let yoyDiff: Int
    let yoyPct: Double
    let shareOfTotal: Double
    var plans: [PlanBreakdown] = []
}

struct PlanBreakdown: Identifiable {
    let id: String // contract_id-plan_id
    let contractID: String
    let planID: String
    let name: String
    let enrollment: Int
    let momDiff: Int
    let momPct: Double
    let yoyDiff: Int
    let yoyPct: Double
    let shareOfTotal: Double
}

struct PlanOption: Identifiable, Equatable {
    let id: String // contract_id-plan_id
    let name: String
    let carrier: String
    let enrollment: Int
}
