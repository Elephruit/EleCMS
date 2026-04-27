import SwiftUI
import Charts

struct GeographicDeepDiveView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    @Binding var selectedDestination: NavDestination
    
    @State private var availablePeriods: [Period] = []
    @State private var selectedPeriod: Period?
    @State private var isLoading = false
    
    // Core Market Stats
    @State private var totalMarket: SegmentStats = .empty
    @State private var snpMarket: SegmentStats = .empty
    @State private var egwpMarket: SegmentStats = .empty
    @State private var individualNonSNPMarket: SegmentStats = .empty
    @State private var pdpEGWPMarket: SegmentStats = .empty
    @State private var pdpIndividualMarket: SegmentStats = .empty
    
    @State private var carrierEnrollments: [EnrollmentByCarrier] = []
    @State private var trendData: [TrendPoint] = []
    @State private var carrierTrendData: [CarrierTrendPoint] = []
    @State private var top5CarrierNames: [String] = []
    
    @State private var selectedState: String?
    @State private var availableStates: [StateOption] = []
    @State private var isStatePickerPresented = false
    @State private var stateSearchText = ""
    
    @State private var selectedSegment: MarketSegment = .total
    
    // Drill-down data
    @State private var expandedCarrier: String? = nil
    @State private var expandedType: String? = nil
    @State private var carrierBreakdowns: [String: GeographicBreakdown] = [:]
    
    // Chart Interactions
    @State private var rawSelectedDate: Date?
    @State private var rawCarrierSelectedDate: Date?
    
    struct SegmentStats {
        var enrollment: Int = 0
        var momDiff: Int = 0
        var momPct: Double = 0
        var ytdDiff: Int = 0
        var ytdPct: Double = 0
        static let empty = SegmentStats()
    }
    
    struct StateOption: Identifiable, Equatable {
        var id: String { abbrev }
        let abbrev: String
        let fullName: String
        let enrollment: Int
    }
    
    var body: some View {
        GeometryReader { mainGeo in
            ZStack(alignment: .top) {
                AppColors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    PageHeader(
                        title: "Geographic Deep-dive",
                        subtitle: selectedStateName,
                        isMenuOpen: $isMenuOpen
                    )
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            stateSelector
                            
                            if selectedState != nil {
                                periodPicker
                                dashboardContent
                            } else {
                                selectStatePrompt
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.bottom, 60)
                    }
                }
                
                if isStatePickerPresented {
                    StatePickerSheet(
                        states: availableStates,
                        selectedState: selectedState,
                        searchText: $stateSearchText,
                        isPresented: $isStatePickerPresented,
                        screenSize: mainGeo.size,
                        onSelect: { state in
                            selectedState = state.abbrev
                            fetchData()
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
            fetchPeriods()
            fetchAvailableStates()
        }
    }
    
    var selectedStateName: String? {
        guard let s = selectedState else { return nil }
        return StateHelper.fullName(for: s)
    }
    
    var stateSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            CustomSectionHeader(title: "Select Geography")
            
            Button(action: {
                stateSearchText = ""
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isStatePickerPresented = true
                }
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedStateName ?? "Select State")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        if let stateOption = selectedStateOption {
                            Text("\(UIFormatter.compactFormat(stateOption.enrollment)) total enrollment")
                                .font(.caption).foregroundColor(.gray)
                        } else {
                            Text("Search states by volume").font(.caption).foregroundColor(.gray)
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
    
    var selectedStateOption: StateOption? {
        guard let selectedState else { return nil }
        return availableStates.first { $0.abbrev == selectedState }
    }
    
    var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availablePeriods) { period in
                    Button(action: {
                        selectedPeriod = period
                        fetchData()
                    }) {
                        Text(period.shortName)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.vertical, 8).padding(.horizontal, 14)
                            .background(selectedPeriod?.id == period.id ? Color.blue : AppColors.surface)
                            .foregroundColor(.white).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Highlights
            HStack(spacing: 8) {
                segmentCard(title: "Market", stats: totalMarket, segment: .total)
                segmentCard(title: "SNP", stats: snpMarket, segment: .snp)
                segmentCard(title: "EGWP (non-PDP)", stats: egwpMarket, segment: .egwpNonPDP)
                segmentCard(title: "Individual non-SNP", stats: individualNonSNPMarket, segment: .individualNonSNP)
                segmentCard(title: "PDP Group", stats: pdpEGWPMarket, segment: .pdpGroup)
                segmentCard(title: "PDP Individual", stats: pdpIndividualMarket, segment: .pdpIndividual)
            }
            .padding(.horizontal)
            
            // Side-by-Side Charts
            HStack(alignment: .top, spacing: 16) {
                MarketTrendChart(trendData: trendData, rawSelectedDate: $rawSelectedDate, chartDomain: chartDomain)
                CarrierComparisonChart(carrierTrendData: carrierTrendData, top5CarrierNames: top5CarrierNames, rawCarrierSelectedDate: $rawCarrierSelectedDate)
            }
            .padding(.horizontal)
            
            // Expandable Carrier Table
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Carrier Performance in \(selectedStateName ?? "State")", subtitle: "\(UIFormatter.formatNumber(currentSegmentEnrollment)) Segment Total")
                
                VStack(spacing: 12) {
                    let maxEnroll = carrierEnrollments.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(carrierEnrollments.enumerated()), id: \.element.id) { index, item in
                        carrierRow(index: index, item: item, maxEnroll: maxEnroll)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    func carrierRow(index: Int, item: EnrollmentByCarrier, maxEnroll: Int) -> some View {
        let isExpanded = expandedCarrier == item.carrier
        
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if isExpanded { expandedCarrier = nil; expandedType = nil }
                    else { expandedCarrier = item.carrier; fetchCarrierBreakdown(item.carrier, enrollment: item.enrollment) }
                }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("#\(index + 1) \(item.carrier)").font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(UIFormatter.compactFormat(item.enrollment)).font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(.white)
                            Text(String(format: "%.1f%%", currentSegmentEnrollment > 0 ? Double(item.enrollment) / Double(currentSegmentEnrollment) * 100 : 0)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)).frame(height: 4)
                            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * CGFloat(item.enrollment) / CGFloat(maxEnroll), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding()
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isExpanded ? Color.blue.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                if let breakdown = carrierBreakdowns[item.carrier] {
                    VStack(spacing: 1) {
                        ForEach(breakdown.types) { type in
                            typeRow(type)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    ProgressView().padding()
                }
            }
        }
    }
    
    @ViewBuilder
    func typeRow(_ type: ProductTypeBreakdown) -> some View {
        let isTypeExpanded = expandedType == type.id
        
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring()) {
                    expandedType = isTypeExpanded ? nil : type.id
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.id.uppercased()).font(.system(size: 11, weight: .black)).foregroundColor(.white)
                        Text(String(format: "%.1f%% of state segment", type.shareOfTotal * 100)).font(.system(size: 9)).foregroundColor(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(UIFormatter.formatNumber(type.enrollment)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                        HStack(spacing: 8) {
                            miniGrowth(label: "MOM", diff: type.momDiff, pct: type.momPct)
                            miniGrowth(label: "YOY", diff: type.yoyDiff, pct: type.yoyPct)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundColor(.gray).rotationEffect(.degrees(isTypeExpanded ? 90 : 0))
                }
                .padding()
                .background(Color.white.opacity(0.03))
            }
            .buttonStyle(.plain)
            
            if isTypeExpanded {
                VStack(spacing: 1) {
                    ForEach(type.plans) { plan in
                        planRow(plan)
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    @ViewBuilder
    func planRow(_ plan: PlanBreakdown) -> some View {
        Button(action: {
            withAnimation(.spring()) {
                selectedDestination = .planDeepDive(id: plan.id)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    Text(plan.id).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(UIFormatter.formatNumber(plan.enrollment)).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                    HStack(spacing: 8) {
                        miniGrowth(label: "MOM", diff: plan.momDiff, pct: plan.momPct)
                        miniGrowth(label: "YOY", diff: plan.yoyDiff, pct: plan.yoyPct)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .background(Color.white.opacity(0.01))
        }
        .buttonStyle(.plain)
    }
    
    func miniGrowth(label: String, diff: Int, pct: Double) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 7, weight: .bold)).foregroundColor(.gray)
            Text("\(diff >= 0 ? "+" : "")\(UIFormatter.compactFormat(diff))").font(.system(size: 8, weight: .bold)).foregroundColor(diff >= 0 ? .green : .red)
            Text(String(format: "(%.1f%%)", pct)).font(.system(size: 8)).foregroundColor(diff >= 0 ? .green : .red)
        }
    }
    
    var currentSegmentEnrollment: Int {
        switch selectedSegment {
        case .total: return totalMarket.enrollment
        case .snp: return snpMarket.enrollment
        case .egwpNonPDP: return egwpMarket.enrollment
        case .individualNonSNP: return individualNonSNPMarket.enrollment
        case .pdpGroup: return pdpEGWPMarket.enrollment
        case .pdpIndividual: return pdpIndividualMarket.enrollment
        }
    }
    
    func segmentCard(title: String, stats: SegmentStats, segment: MarketSegment) -> some View {
        EnrollmentMetricCard(
            title: title,
            enrollment: stats.enrollment,
            momDiff: stats.momDiff,
            momPct: stats.momPct,
            ytdDiff: stats.ytdDiff,
            ytdPct: stats.ytdPct,
            isSelected: selectedSegment == segment
        )
        .onTapGesture {
            withAnimation(.spring()) {
                selectedSegment = segment
                fetchData()
            }
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
    
    var selectStatePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
            Text("Select a State").font(.headline).foregroundColor(.white)
            Text("Search for a state to view detailed geographic market performance and leader comparisons.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }
    
    func fetchPeriods() {
        Task {
            do {
                let rows = try dataStore.database.query(sql: "SELECT period_id, year, month FROM periods ORDER BY year DESC, month DESC")
                let periods = rows.map { Period(id: $0["period_id"] as? Int ?? 0, year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0) }
                await MainActor.run {
                    self.availablePeriods = periods
                    if self.selectedPeriod == nil { self.selectedPeriod = periods.first }
                }
            } catch { print("Periods failed: \(error)") }
        }
    }
    
    func fetchAvailableStates() {
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let pid = pRow.first?["period_id"] as? Int else { return }
                
                let rows = try dataStore.database.query(sql: """
                    SELECT state, SUM(enrollment) as total
                    FROM enrollment_records e
                    JOIN county_dim co ON co.county_id = e.county_id
                    WHERE e.period_id = \(pid) AND state != ''
                    GROUP BY state
                    ORDER BY total DESC
                """)
                let states = rows.compactMap { row -> StateOption? in
                    guard let abbrev = row["state"] as? String else { return nil }
                    return StateOption(abbrev: abbrev, fullName: StateHelper.fullName(for: abbrev), enrollment: row["total"] as? Int ?? 0)
                }
                await MainActor.run { self.availableStates = states }
            } catch { print("States failed: \(error)") }
        }
    }
    
    func fetchCarrierBreakdown(_ carrierName: String, enrollment: Int) {
        guard let period = selectedPeriod, let state = selectedState else { return }
        Task {
            do {
                let focusFilter = selectedSegment.sqlFilter
                let pmID = try getPriorPeriodID(period)
                let pyID = try getPriorYearPeriodID(period)
                
                let sql = """
                    SELECT 
                        p.type, 
                        p.name as plan_name, 
                        p.cms_plan_id, 
                        p.contract_id,
                        SUM(CASE WHEN e.period_id = \(period.id) THEN e.enrollment ELSE 0 END) as cur_e,
                        SUM(CASE WHEN e.period_id = \(pmID ?? -1) THEN e.enrollment ELSE 0 END) as pm_e,
                        SUM(CASE WHEN e.period_id = \(pyID ?? -1) THEN e.enrollment ELSE 0 END) as py_e
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    JOIN county_dim co ON co.county_id = e.county_id
                    WHERE co.state = '\(state)' 
                      AND c.name = ?
                      AND e.period_id IN (\(period.id), \(pmID ?? -1), \(pyID ?? -1))
                      \(focusFilter)
                    GROUP BY p.type, p.plan_id
                """
                
                let rows = try dataStore.database.query(sql: sql, arguments: [carrierName])
                
                var typeMap: [String: ProductTypeBreakdown] = [:]
                let stateTotal = Double(currentSegmentEnrollment)
                
                for row in rows {
                    let typeName = row["type"] as? String ?? "Other"
                    let contractID = row["contract_id"] as? String ?? ""
                    let cmsPlanID = row["cms_plan_id"] as? String ?? ""
                    let planID = "\(contractID)-\(cmsPlanID)"
                    let planName = row["plan_name"] as? String ?? "Unknown Plan"
                    let curE = row["cur_e"] as? Int ?? 0
                    let pmE = row["pm_e"] as? Int ?? 0
                    let pyE = row["py_e"] as? Int ?? 0
                    
                    let planBreakdown = PlanBreakdown(
                        id: planID,
                        contractID: contractID,
                        planID: cmsPlanID,
                        name: planName,
                        enrollment: curE,
                        momDiff: curE - pmE,
                        momPct: pmE > 0 ? (Double(curE - pmE) / Double(pmE)) * 100 : 0,
                        yoyDiff: curE - pyE,
                        yoyPct: pyE > 0 ? (Double(curE - pyE) / Double(pyE)) * 100 : 0,
                        shareOfTotal: stateTotal > 0 ? Double(curE) / stateTotal : 0
                    )
                    
                    var typeBreakdown = typeMap[typeName] ?? ProductTypeBreakdown(
                        id: typeName, enrollment: 0, momDiff: 0, momPct: 0, yoyDiff: 0, yoyPct: 0, shareOfTotal: 0, plans: []
                    )
                    
                    typeBreakdown.plans.append(planBreakdown)
                    typeMap[typeName] = typeBreakdown
                }
                
                let sortedTypes = typeMap.values.map { type -> ProductTypeBreakdown in
                    let totalE = type.plans.reduce(0) { $0 + $1.enrollment }
                    let totalPM = type.plans.reduce(0) { $0 + ($1.enrollment - $1.momDiff) }
                    let totalPY = type.plans.reduce(0) { $0 + ($1.enrollment - $1.yoyDiff) }
                    
                    return ProductTypeBreakdown(
                        id: type.id,
                        enrollment: totalE,
                        momDiff: totalE - totalPM,
                        momPct: totalPM > 0 ? (Double(totalE - totalPM) / Double(totalPM)) * 100 : 0,
                        yoyDiff: totalE - totalPY,
                        yoyPct: totalPY > 0 ? (Double(totalE - totalPY) / Double(totalPY)) * 100 : 0,
                        shareOfTotal: stateTotal > 0 ? Double(totalE) / stateTotal : 0,
                        plans: type.plans.sorted(by: { $0.enrollment > $1.enrollment })
                    )
                }.sorted(by: { $0.enrollment > $1.enrollment })
                
                await MainActor.run {
                    self.carrierBreakdowns[carrierName] = GeographicBreakdown(id: carrierName, enrollment: enrollment, types: sortedTypes)
                }
            } catch { print("Breakdown failed: \(error)") }
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
    
    func fetchData() {
        guard let period = selectedPeriod, let state = selectedState else { return }
        isLoading = true
        expandedCarrier = nil
        expandedType = nil
        carrierBreakdowns.removeAll()
        
        Task {
            do {
                let andClause = " AND co.state = '\(state)'"
                let focusFilter = selectedSegment.sqlFilter
                let ytdDecID = try dataStore.database.query(sql: "SELECT period_id FROM periods WHERE year = \(period.year - 1) AND month = 12").first?["period_id"] as? Int
                let pmID = try getPriorPeriodID(period)
                
                let segments = [
                    (name: "Total", segment: MarketSegment.total),
                    (name: "SNP", segment: MarketSegment.snp),
                    (name: "EGWP", segment: MarketSegment.egwpNonPDP),
                    (name: "IndivNonSNP", segment: MarketSegment.individualNonSNP),
                    (name: "PDP_EGWP", segment: MarketSegment.pdpGroup),
                    (name: "PDP_Indiv", segment: MarketSegment.pdpIndividual)
                ]
                
                var segmentResults: [String: SegmentStats] = [:]
                for seg in segments {
                    let sFilter = seg.segment.sqlFilter
                    let curSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id WHERE e.period_id = \(period.id) \(andClause) \(sFilter)"
                    let pmSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id WHERE e.period_id = \(pmID ?? -1) \(andClause) \(sFilter)"
                    let pdSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id WHERE e.period_id = \(ytdDecID ?? -1) \(andClause) \(sFilter)"
                    
                    let curT = (try dataStore.database.query(sql: curSQL)).first?["total"] as? Int ?? 0
                    let pmT = (try dataStore.database.query(sql: pmSQL)).first?["total"] as? Int ?? 0
                    let pdT = (try dataStore.database.query(sql: pdSQL)).first?["total"] as? Int ?? 0
                    
                    var stats = SegmentStats()
                    stats.enrollment = curT; stats.momDiff = curT - pmT
                    stats.momPct = pmT > 0 ? (Double(stats.momDiff) / Double(pmT)) * 100.0 : 0
                    stats.ytdDiff = curT - pdT
                    stats.ytdPct = pdT > 0 ? (Double(stats.ytdDiff) / Double(pdT)) * 100.0 : 0
                    segmentResults[seg.name] = stats
                }

                let trendRows = try dataStore.database.query(sql: "SELECT pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE co.state = '\(state)' \(focusFilter) GROUP BY pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC")
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }

                let carrierRows = try dataStore.database.query(sql: "SELECT c.name as carrier, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id WHERE e.period_id = \(period.id) \(andClause) \(focusFilter) GROUP BY c.carrier_id ORDER BY total DESC LIMIT 20")
                let carriers = carrierRows.map { EnrollmentByCarrier(carrier: $0["carrier"] as? String ?? "Unknown", enrollment: $0["total"] as? Int ?? 0) }
                
                let top5Names = Array(carriers.prefix(5)).map { $0.carrier }
                var carrierTrend: [CarrierTrendPoint] = []
                if !top5Names.isEmpty {
                    let carrierList = top5Names.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
                    let ctSQL = "SELECT c.name as carrier, pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE co.state = '\(state)' \(focusFilter) AND c.name IN (\(carrierList)) GROUP BY c.name, pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC"
                    let ctRows = try dataStore.database.query(sql: ctSQL)
                    carrierTrend = ctRows.map { CarrierTrendPoint(carrier: $0["carrier"] as? String ?? "", year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }
                }
                
                await MainActor.run {
                    self.totalMarket = segmentResults["Total"] ?? .empty
                    self.snpMarket = segmentResults["SNP"] ?? .empty
                    self.egwpMarket = segmentResults["EGWP"] ?? .empty
                    self.individualNonSNPMarket = segmentResults["IndivNonSNP"] ?? .empty
                    self.pdpEGWPMarket = segmentResults["PDP_EGWP"] ?? .empty
                    self.pdpIndividualMarket = segmentResults["PDP_Indiv"] ?? .empty
                    
                    self.trendData = trend
                    self.carrierTrendData = carrierTrend
                    self.top5CarrierNames = top5Names
                    self.carrierEnrollments = carriers
                    self.isLoading = false
                }
            } catch { print("Fetch failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
}

struct StatePickerSheet: View {
    let states: [GeographicDeepDiveView.StateOption]
    let selectedState: String?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let screenSize: CGSize
    let onSelect: (GeographicDeepDiveView.StateOption) -> Void
    
    private var filteredStates: [GeographicDeepDiveView.StateOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return states }
        return states.filter { $0.fullName.localizedCaseInsensitiveContains(query) || $0.abbrev.localizedCaseInsensitiveContains(query) }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { close() }
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 40, height: 6).padding(.top, 10).padding(.bottom, 14)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select State").font(.headline).foregroundColor(.white)
                        Text(searchText.isEmpty ? "All available territories" : "\(filteredStates.count) matching states").font(.caption).foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray) }.buttonStyle(.plain)
                }
                .padding(.horizontal).padding(.bottom, 16)
                
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .bold)).foregroundColor(.gray)
                    TextField("Search states", text: $searchText).textInputAutocapitalization(.words).disableAutocorrection(true).foregroundColor(.white)
                    if !searchText.isEmpty { Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundColor(.gray) }.buttonStyle(.plain) }
                }
                .padding(14).background(Color.white.opacity(0.06)).cornerRadius(14).padding(.horizontal).padding(.bottom, 12)
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredStates) { state in
                            Button(action: { onSelect(state); close() }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12).fill(selectedState == state.abbrev ? Color.blue.opacity(0.22) : Color.white.opacity(0.06)).frame(width: 44, height: 44)
                                        Text(state.abbrev).font(.system(size: 14, weight: .bold)).foregroundColor(selectedState == state.abbrev ? .blue : .gray)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(state.fullName).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                                        Text("\(UIFormatter.compactFormat(state.enrollment)) latest enrollment").font(.caption).foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.gray.opacity(0.7))
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
