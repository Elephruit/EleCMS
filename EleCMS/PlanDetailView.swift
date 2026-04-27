import SwiftUI
import Charts
import MapKit

struct PlanDetailView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    let initialPlanID: String? // contractID-planID
    
    @State private var selectedPlanID: String?
    @State private var planDetails: PlanDetailData?
    @State private var availablePlans: [PlanOption] = []
    @State private var isPlanPickerPresented = false
    @State private var planSearchText = ""
    @State private var isLoading = false
    
    @State private var trendData: [TrendPoint] = []
    @State private var countyEnrollments: [PlanCountyEnrollment] = []
    
    struct PlanDetailData {
        let contractID: String
        let planID: String
        let name: String
        let carrier: String
        let type: String
        let premium: Double?
        let deductible: Double?
        let enrollment: Int
        let momDiff: Int
        let momPct: Double
        let yoyDiff: Int
        let yoyPct: Double
    }
    
    struct PlanCountyEnrollment: Identifiable {
        let id: String // County Name
        let state: String
        let fips: String
        let enrollment: Int
    }
    
    @State private var footprintFIPS: Set<String> = []
    @State private var footprintStates: Set<String> = []
    
    init(dataStore: DataStore, isMenuOpen: Binding<Bool>, planID: String? = nil) {
        self.dataStore = dataStore
        self._isMenuOpen = isMenuOpen
        self.initialPlanID = planID
    }
    
    var body: some View {
        GeometryReader { mainGeo in
            ZStack(alignment: .top) {
                AppColors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    PageHeader(
                        title: "Plan Deep-dive",
                        subtitle: planDetails?.name ?? selectedPlanID,
                        isMenuOpen: $isMenuOpen
                    )
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            planSelector
                            
                            if let details = planDetails {
                                planContent(details)
                            } else {
                                selectPlanPrompt
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.bottom, 60)
                    }
                }
                
                if isPlanPickerPresented {
                    PlanPickerSheet(
                        plans: availablePlans,
                        selectedPlanID: selectedPlanID,
                        searchText: $planSearchText,
                        isPresented: $isPlanPickerPresented,
                        screenSize: mainGeo.size,
                        onSelect: { plan in
                            selectedPlanID = plan.id
                            fetchPlanData(planID: plan.id)
                        }
                    )
                    .zIndex(100)
                }
                
                if isLoading {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
        }
        .onAppear {
            fetchAvailablePlans()
            if let pid = initialPlanID {
                selectedPlanID = pid
                fetchPlanData(planID: pid)
            }
        }
    }
    
    var planSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            CustomSectionHeader(title: "Select Plan")
            
            Button(action: {
                planSearchText = ""
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isPlanPickerPresented = true
                }
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planDetails?.name ?? "Search Plans")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let details = planDetails {
                            Text("\(details.contractID)-\(details.planID) • \(details.carrier)")
                                .font(.caption).foregroundColor(.gray)
                        } else {
                            Text("Search by Name, Contract, or ID").font(.caption).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .bold)).foregroundColor(.gray)
                }
                .padding(16).background(AppColors.surface).cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.horizontal)
        }
    }
    
    @ViewBuilder
    func planContent(_ details: PlanDetailData) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Hero Stats
            HStack(spacing: 16) {
                EnrollmentMetricCard(
                    title: "Total Enrollment",
                    enrollment: details.enrollment,
                    momDiff: details.momDiff,
                    momPct: details.momPct,
                    ytdDiff: details.yoyDiff, // Using YOY here as proxy for annual
                    ytdPct: details.yoyPct
                )
                
                VStack(spacing: 12) {
                    attributeCard(label: "Premium", value: details.premium != nil ? String(format: "$%.2f", details.premium!) : "N/A", icon: "dollarsign.circle")
                    attributeCard(label: "Type", value: details.type, icon: "tag")
                }
                .frame(width: 150)
            }
            .padding(.horizontal)
            
            // Trend
            MarketTrendChart(trendData: trendData, rawSelectedDate: .constant(nil), chartDomain: chartDomain)
                .padding(.horizontal)
            
            // Service Area Map
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Service Area Footprint", subtitle: "\(footprintFIPS.count) Counties Offered")
                
                ModernCard {
                    VStack(spacing: 0) {
                        CountyMapView(footprintFIPS: footprintFIPS, states: footprintStates)
                            .frame(height: 300)
                            .cornerRadius(12)
                        
                        Divider().background(Color.white.opacity(0.1)).padding(.vertical, 12)
                        
                        // Top Counties List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TOP COUNTIES BY ENROLLMENT").font(.system(size: 9, weight: .black)).foregroundColor(.gray)
                            
                            ForEach(countyEnrollments.prefix(5)) { ce in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ce.id).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                        Text(ce.state).font(.system(size: 9, weight: .black)).foregroundColor(.blue)
                                    }
                                    Spacer()
                                    Text(UIFormatter.formatNumber(ce.enrollment)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    func attributeCard(label: String, value: String, icon: String) -> some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 8)).foregroundColor(.blue)
                    Text(label.uppercased()).font(.system(size: 8, weight: .black)).foregroundColor(.gray)
                }
                Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    var chartDomain: ClosedRange<Int> {
        let enrollments = trendData.map { $0.enrollment }
        let minValue = enrollments.min() ?? 0
        let maxValue = enrollments.max() ?? 1000
        let rangeVal = maxValue - minValue
        let padding = rangeVal > 0 ? Double(rangeVal) * 0.2 : Double(maxValue) * 0.1
        return Swift.max(0, Int(Double(minValue) - padding))...Int(Double(maxValue) + padding)
    }
    
    var selectPlanPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
            Text("Select a Plan").font(.headline).foregroundColor(.white)
            Text("Enter a Plan ID or name to view detailed enrollment trends, premiums, and geographic footprint.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }
    
    func fetchAvailablePlans() {
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let pid = pRow.first?["period_id"] as? Int else { return }
                
                let sql = """
                    SELECT p.contract_id, p.cms_plan_id, p.name, c.name as carrier, SUM(e.enrollment) as total
                    FROM plan_dim p
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    JOIN enrollment_records e ON e.plan_id = p.plan_id
                    WHERE e.period_id = \(pid)
                    GROUP BY p.plan_id
                    ORDER BY total DESC
                    LIMIT 200
                """
                let rows = try dataStore.database.query(sql: sql)
                let plans = rows.map { row in
                    PlanOption(
                        id: "\(row["contract_id"] ?? "")-\(row["cms_plan_id"] ?? "")",
                        name: row["name"] as? String ?? "Unknown Plan",
                        carrier: row["carrier"] as? String ?? "Unknown Carrier",
                        enrollment: row["total"] as? Int ?? 0
                    )
                }
                await MainActor.run { self.availablePlans = plans }
            } catch { print("Plans failed: \(error)") }
        }
    }
    
    func fetchPlanData(planID: String) {
        isLoading = true
        let parts = planID.split(separator: "-")
        guard parts.count == 2 else { isLoading = false; return }
        let contractID = String(parts[0])
        let cmsPlanID = String(parts[1])
        
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id, year, month FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let currentPeriod = pRow.first.map({ Period(id: $0["period_id"] as? Int ?? 0, year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0) }) else { isLoading = false; return }
                
                let pmID = try getPriorPeriodID(currentPeriod)
                let pyID = try getPriorYearPeriodID(currentPeriod)
                
                // 1. Basic Details
                let detailSQL = """
                    SELECT p.*, c.name as carrier_name, l.monthly_premium, l.deductible,
                        SUM(CASE WHEN e.period_id = \(currentPeriod.id) THEN e.enrollment ELSE 0 END) as cur_e,
                        SUM(CASE WHEN e.period_id = \(pmID ?? -1) THEN e.enrollment ELSE 0 END) as pm_e,
                        SUM(CASE WHEN e.period_id = \(pyID ?? -1) THEN e.enrollment ELSE 0 END) as py_e
                    FROM plan_dim p
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    LEFT JOIN landscape_records l ON l.plan_id = p.plan_id AND l.year = \(currentPeriod.year)
                    LEFT JOIN enrollment_records e ON e.plan_id = p.plan_id
                    WHERE p.contract_id = ? AND p.cms_plan_id = ?
                    GROUP BY p.plan_id
                """
                let details = try dataStore.database.query(sql: detailSQL, arguments: [contractID, cmsPlanID])
                guard let d = details.first else { isLoading = false; return }
                
                let curE = d["cur_e"] as? Int ?? 0
                let pmE = d["pm_e"] as? Int ?? 0
                let pyE = d["py_e"] as? Int ?? 0
                
                let detailData = PlanDetailData(
                    contractID: contractID,
                    planID: cmsPlanID,
                    name: d["name"] as? String ?? "Unknown Plan",
                    carrier: d["carrier_name"] as? String ?? "Unknown Carrier",
                    type: d["type"] as? String ?? "N/A",
                    premium: d["monthly_premium"] as? Double,
                    deductible: d["deductible"] as? Double,
                    enrollment: curE,
                    momDiff: curE - pmE,
                    momPct: pmE > 0 ? (Double(curE - pmE) / Double(pmE)) * 100 : 0,
                    yoyDiff: curE - pyE,
                    yoyPct: pyE > 0 ? (Double(curE - pyE) / Double(pyE)) * 100 : 0
                )
                
                // 2. Trend
                let trendRows = try dataStore.database.query(sql: """
                    SELECT pe.year, pe.month, SUM(e.enrollment) as total
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN periods pe ON pe.period_id = e.period_id
                    WHERE p.contract_id = ? AND p.cms_plan_id = ?
                    GROUP BY pe.period_id
                    ORDER BY pe.year ASC, pe.month ASC
                """, arguments: [contractID, cmsPlanID])
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }
                
                // 3. Geographic Footprint (From Landscape)
                // Use the latest available year in PSA that is <= current period year
                let footprintRows = try dataStore.database.query(sql: """
                    SELECT co.name, co.state, co.fips_county_code
                    FROM plan_service_area psa
                    JOIN plan_dim p ON p.plan_id = psa.plan_id
                    JOIN county_dim co ON co.county_id = psa.county_id
                    WHERE p.contract_id = ? AND p.cms_plan_id = ? 
                    AND psa.year = (SELECT MAX(year) FROM plan_service_area WHERE plan_id = p.plan_id AND year <= \(currentPeriod.year))
                """, arguments: [contractID, cmsPlanID])
                
                let footprint = footprintRows.map { row in
                    let rawFips = row["fips_county_code"] as? String ?? ""
                    let paddedFips = rawFips.count == 4 ? "0\(rawFips)" : rawFips
                    return PlanCountyEnrollment(
                        id: row["name"] as? String ?? "",
                        state: row["state"] as? String ?? "",
                        fips: paddedFips,
                        enrollment: 0
                    )
                }
                
                // 4. Enrollment Data
                let enrollmentRows = try dataStore.database.query(sql: """
                    SELECT co.name, co.state, co.fips_county_code, e.enrollment
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN county_dim co ON co.county_id = e.county_id
                    WHERE p.contract_id = ? AND p.cms_plan_id = ? AND e.period_id = \(currentPeriod.id)
                    ORDER BY e.enrollment DESC
                """, arguments: [contractID, cmsPlanID])
                
                let enrollmentCounties = enrollmentRows.map { row in
                    let rawFips = row["fips_county_code"] as? String ?? ""
                    let paddedFips = rawFips.count == 4 ? "0\(rawFips)" : rawFips
                    return PlanCountyEnrollment(
                        id: row["name"] as? String ?? "",
                        state: row["state"] as? String ?? "",
                        fips: paddedFips,
                        enrollment: row["enrollment"] as? Int ?? 0
                    )
                }
                
                var fipsSet = Set(footprint.map { $0.fips })
                if fipsSet.isEmpty {
                    // Fallback to enrollment counties if footprint is empty
                    fipsSet = Set(enrollmentCounties.map { $0.fips })
                }
                
                let allStates = Set(footprint.map { $0.state })
                    .union(Set(enrollmentCounties.map { $0.state }))
                    .filter { !$0.isEmpty && $0 != "??" }
                
                await MainActor.run {
                    self.planDetails = detailData
                    self.trendData = trend
                    self.countyEnrollments = enrollmentCounties
                    self.footprintFIPS = fipsSet
                    self.footprintStates = allStates
                    self.isLoading = false
                }
            } catch { print("Plan data failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
    
    private func getPriorPeriodID(_ p: Period) throws -> Int? {
        let pm = p.month == 1 ? 12 : p.month - 1
        let py = p.month == 1 ? p.year - 1 : p.year
        let r = try dataStore.database.query(sql: "SELECT period_id FROM periods WHERE year = \(py) AND month = \(pm)")
        return r.first?["period_id"] as? Int
    }
    
    private func getPriorYearPeriodID(_ p: Period) throws -> Int? {
        let r = try dataStore.database.query(sql: "SELECT period_id FROM periods WHERE year = \(p.year - 1) AND month = \(p.month)")
        return r.first?["period_id"] as? Int
    }
}

struct PlanPickerSheet: View {
    let plans: [PlanOption]
    let selectedPlanID: String?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let screenSize: CGSize
    let onSelect: (PlanOption) -> Void
    
    private var filteredPlans: [PlanOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return plans }
        return plans.filter { 
            $0.name.localizedCaseInsensitiveContains(query) || 
            $0.id.localizedCaseInsensitiveContains(query) ||
            $0.carrier.localizedCaseInsensitiveContains(query)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { close() }
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 40, height: 6).padding(.top, 10).padding(.bottom, 14)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select Plan").font(.headline).foregroundColor(.white)
                        Text(searchText.isEmpty ? "Top plans by enrollment" : "\(filteredPlans.count) matching plans").font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray) }.buttonStyle(.plain)
                }
                .padding(.horizontal).padding(.bottom, 16)
                
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold)).foregroundColor(.gray)
                    TextField("Search Name or Plan ID", text: $searchText).textInputAutocapitalization(.never).disableAutocorrection(true).foregroundColor(.white)
                    if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundColor(.gray) }.buttonStyle(.plain) }
                }
                .padding(14).background(Color.white.opacity(0.06)).cornerRadius(14).padding(.horizontal).padding(.bottom, 12)
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPlans) { plan in
                            Button(action: { onSelect(plan); close() }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12).fill(selectedPlanID == plan.id ? Color.blue.opacity(0.22) : Color.white.opacity(0.06)).frame(width: 44, height: 44)
                                        Image(systemName: "doc.text").font(.system(size: 16, weight: .bold)).foregroundColor(selectedPlanID == plan.id ? .blue : .gray)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(plan.name).font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                                        Text("\(plan.id) • \(plan.carrier)").font(.system(size: 10)).foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text(UIFormatter.compactFormat(plan.enrollment)).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                }
                                .padding(14).background(AppColors.surface).cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 36)
                }
            }
            .frame(maxHeight: screenSize.height * 0.78).background(AppColors.background)
            .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        }
        .ignoresSafeArea()
    }
    
    private func close() { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }
}
