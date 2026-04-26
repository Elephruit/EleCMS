import SwiftUI
import Charts

struct DashboardView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    
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
    @State private var countyEnrollments: [EnrollmentByCountyByPlan] = []
    @State private var trendData: [TrendPoint] = []
    @State private var carrierTrendData: [CarrierTrendPoint] = []
    @State private var top5CarrierNames: [String] = []
    
    @State private var isFilterPresented = false
    @State private var filter = DashboardFilter()
    @State private var selectedSegment: MarketSegment = .total
    
    @State private var availableStates: [String] = []
    @State private var availablePlanTypes: [String] = []
    
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
    
    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                PageHeader(
                    title: "Market Overview",
                    subtitle: selectedPeriod?.name,
                    isMenuOpen: $isMenuOpen,
                    rightButton: AnyView(
                        Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isFilterPresented = true } }) {
                            ZStack {
                                Circle().fill(AppColors.surface).frame(width: 40, height: 40)
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(filterActive ? .orange : .white)
                            }
                        }
                    )
                )
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        periodPicker
                        
                        if isLoading && availablePeriods.isEmpty {
                            ProgressView().tint(.white).padding(.top, 100).frame(maxWidth: .infinity)
                        } else if carrierEnrollments.isEmpty && countyEnrollments.isEmpty && !isLoading {
                            emptyStateView
                        } else {
                            dashboardContent
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            
            if isFilterPresented {
                FilterOverlay(
                    filter: $filter,
                    availableStates: availableStates,
                    availablePlanTypes: availablePlanTypes,
                    isPresented: $isFilterPresented,
                    onApply: fetchData
                )
                .zIndex(100)
            }
            
            if isLoading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView().tint(.white).scaleEffect(1.5)
            }
        }
        .onAppear {
            fetchPeriods()
            fetchFilterOptions()
        }
    }
    
    var filterActive: Bool {
        filter.state != nil || filter.planType != nil || filter.snp != "All" || filter.egwp != "All"
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
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(selectedPeriod?.id == period.id ? Color.blue : AppColors.surface)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
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
            
            // Side-by-Side Trend Charts
            HStack(alignment: .top, spacing: 16) {
                MarketTrendChart(trendData: trendData, rawSelectedDate: $rawSelectedDate, chartDomain: chartDomain)
                CarrierComparisonChart(carrierTrendData: carrierTrendData, top5CarrierNames: top5CarrierNames, rawCarrierSelectedDate: $rawCarrierSelectedDate)
            }
            .padding(.horizontal)
            
            // Carrier List
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "\(selectedSegment.rawValue) Market Share", subtitle: "\(UIFormatter.formatNumber(currentSegmentEnrollment)) Total")
                
                VStack(spacing: 12) {
                    let maxEnroll = carrierEnrollments.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(carrierEnrollments.enumerated()), id: \.element.id) { index, item in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("#\(index + 1) \(item.carrier)").font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(UIFormatter.compactFormat(item.enrollment)).font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(.white)
                                        Text(String(format: "%.1f%%", currentSegmentEnrollment > 0 ? Double(item.enrollment) / Double(currentSegmentEnrollment) * 100 : 0)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)).frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * CGFloat(item.enrollment) / CGFloat(maxEnroll), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
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
    
    var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 64)).foregroundStyle(.gray.opacity(0.3))
            Text("No Matching Data").font(.headline).foregroundColor(.white)
            Text("Try clearing your filters or check the Data tab.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
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
                    fetchData()
                }
            } catch { print("Periods failed: \(error)") }
        }
    }
    
    func fetchFilterOptions() {
        Task {
            do {
                let stateRows = try dataStore.database.query(sql: "SELECT DISTINCT state FROM county_dim WHERE state != '' ORDER BY state")
                let states = stateRows.compactMap { $0["state"] as? String }
                let typeRows = try dataStore.database.query(sql: """
                    SELECT DISTINCT type FROM plan_dim 
                    WHERE type IS NOT NULL AND type != '' 
                    AND type NOT IN ('D-SNP', 'C-SNP', 'I-SNP')
                    ORDER BY type
                """)
                let types = typeRows.compactMap { $0["type"] as? String }
                await MainActor.run { self.availableStates = states; self.availablePlanTypes = types }
            } catch { print("Filter options failed: \(error)") }
        }
    }
    
    func fetchData() {
        guard let period = selectedPeriod else { return }
        isLoading = true
        Task {
            do {
                var conds: [String] = []
                if let s = filter.state { conds.append("co.state = '\(s)'") }
                if let t = filter.planType { conds.append("p.type = '\(t)'") }
                if filter.snp == "Yes" {
                    var snpTypes: [String] = []
                    if filter.dsnp { snpTypes.append("'D-SNP'") }
                    if filter.csnp { snpTypes.append("'C-SNP'") }
                    if filter.isnp { snpTypes.append("'I-SNP'") }
                    if !snpTypes.isEmpty { conds.append("p.snp_type IN (\(snpTypes.joined(separator: ",")))") }
                    else { conds.append("p.is_snp = 1") }
                } else if filter.snp == "No" { conds.append("p.is_snp = 0") }
                if filter.egwp == "Yes" { conds.append("p.is_egwp = 1") }
                else if filter.egwp == "No" { conds.append("p.is_egwp = 0") }
                
                let andClause = conds.isEmpty ? "" : " AND " + conds.joined(separator: " AND ")
                
                let focusFilter = selectedSegment.sqlFilter
                let wherePeriodFocus = " WHERE e.period_id = \(period.id)" + andClause + focusFilter
                let whereTrendFocus = conds.isEmpty ? " WHERE 1=1 \(focusFilter)" : " WHERE " + conds.joined(separator: " AND ") + focusFilter

                let segments = [
                    (name: "Total", segment: MarketSegment.total),
                    (name: "SNP", segment: MarketSegment.snp),
                    (name: "EGWP", segment: MarketSegment.egwpNonPDP),
                    (name: "IndivNonSNP", segment: MarketSegment.individualNonSNP),
                    (name: "PDP_EGWP", segment: MarketSegment.pdpGroup),
                    (name: "PDP_Indiv", segment: MarketSegment.pdpIndividual)
                ]
                
                var segmentResults: [String: SegmentStats] = [:]
                let pm = period.month == 1 ? 12 : period.month - 1
                let py = period.month == 1 ? period.year - 1 : period.year
                
                for seg in segments {
                    let sFilter = seg.segment.sqlFilter
                    let curSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id WHERE e.period_id = \(period.id) \(andClause) \(sFilter)"
                    let pmSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE pe.year = \(py) AND pe.month = \(pm) \(andClause) \(sFilter)"
                    let pdSQL = "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE pe.year = \(period.year - 1) AND pe.month = 12 \(andClause) \(sFilter)"
                    
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

                let trendRows = try dataStore.database.query(sql: "SELECT pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id \(whereTrendFocus) GROUP BY pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC")
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }

                let carrierRows = try dataStore.database.query(sql: "SELECT c.name as carrier, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id \(wherePeriodFocus) GROUP BY c.carrier_id ORDER BY total DESC LIMIT 20")
                let carriers = carrierRows.map { EnrollmentByCarrier(carrier: $0["carrier"] as? String ?? "Unknown", enrollment: $0["total"] as? Int ?? 0) }
                
                let top5Names = Array(carriers.prefix(5)).map { $0.carrier }
                var carrierTrend: [CarrierTrendPoint] = []
                if !top5Names.isEmpty {
                    let carrierList = top5Names.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
                    let ctSQL = "SELECT c.name as carrier, pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id \(whereTrendFocus) AND c.name IN (\(carrierList)) GROUP BY c.name, pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC"
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
                    
                    self.trendData = trend; 
                    self.carrierTrendData = carrierTrend; 
                    self.top5CarrierNames = top5Names;
                    self.carrierEnrollments = carriers; 
                    self.isLoading = false
                }
            } catch { print("Fetch failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
}
