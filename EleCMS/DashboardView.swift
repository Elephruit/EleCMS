import SwiftUI
import Charts

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

struct DashboardView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    
    @State private var countyEnrollments: [EnrollmentByCountyByPlan] = []
    @State private var carrierEnrollments: [EnrollmentByCarrier] = []
    @State private var trendData: [TrendPoint] = []
    @State private var availablePeriods: [Period] = []
    @State private var selectedPeriod: Period?
    @State private var isLoading = false
    
    @State private var totalEnrollment: Int = 0
    @State private var priorMonthEnrollment: Int? = nil
    @State private var priorDecEnrollment: Int? = nil
    
    @State private var isFilterPresented = false
    @State private var filter = DashboardFilter()
    
    @State private var availableStates: [String] = []
    @State private var availablePlanTypes: [String] = []
    
    @State private var selectedDate: Date?
    
    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        periodPicker
                        
                        if carrierEnrollments.isEmpty && countyEnrollments.isEmpty && !isLoading {
                            emptyStateView
                        } else {
                            dashboardContentView
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
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
    
    var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isMenuOpen = true } }) {
                    ZStack {
                        Circle().fill(AppColors.surface).frame(width: 40, height: 40)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Market Overview")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let period = selectedPeriod {
                        Text(period.name.uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isFilterPresented = true } }) {
                    ZStack {
                        Circle().fill(AppColors.surface).frame(width: 40, height: 40)
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(filterActive ? .orange : .white)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 64)
            .background(AppColors.background.opacity(0.95))
            
            Divider().background(Color.white.opacity(0.1))
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
    
    var dashboardContentView: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Summary Cards
            HStack(spacing: 16) {
                ModernCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOTAL MARKET")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(formatNumber(totalEnrollment)) // Full number with commas
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(spacing: 12) {
                    growthMetric(title: "MOM", current: totalEnrollment, prior: priorMonthEnrollment)
                    growthMetric(title: "YTD", current: totalEnrollment, prior: priorDecEnrollment)
                }
                .frame(width: 140)
            }
            .padding(.horizontal)
            
            // Interactive Chart
            if trendData.count > 1 {
                VStack(alignment: .leading, spacing: 16) {
                    Text("GROWTH TREND")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white.opacity(0.4))
                        .kerning(1.2)
                        .padding(.horizontal)
                    
                    ModernCard {
                        VStack(alignment: .leading, spacing: 12) {
                            if let selectedDate = selectedDate, let point = trendData.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(point.date, format: .dateTime.month().year())
                                            .font(.caption.bold())
                                            .foregroundColor(.blue)
                                        Text(compactFormat(point.enrollment))
                                            .font(.headline.bold())
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                }
                            } else {
                                Text("Slide to inspect history").font(.caption).foregroundColor(.gray)
                            }
                            
                            Chart {
                                ForEach(trendData) { point in
                                    LineMark(x: .value("Date", point.date), y: .value("Enrollment", point.enrollment))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                        .interpolationMethod(.catmullRom)
                                        .lineStyle(StrokeStyle(lineWidth: 3))
                                    
                                    if let selectedDate = selectedDate, Calendar.current.isDate(point.date, inSameDayAs: selectedDate) {
                                        RuleMark(x: .value("Date", selectedDate))
                                            .foregroundStyle(Color.white.opacity(0.5))
                                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                                        
                                        PointMark(x: .value("Date", selectedDate), y: .value("Enrollment", point.enrollment))
                                            .foregroundStyle(.blue)
                                            .symbolSize(100)
                                    }
                                }
                            }
                            .chartYScale(domain: chartDomain)
                            .chartXSelection(value: $selectedDate)
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                                    AxisValueLabel {
                                        if let intVal = value.as(Int.self) {
                                            Text(compactFormat(intVal))
                                        }
                                    }
                                }
                            }
                            .frame(height: 180)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Carriers
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("CARRIER MARKET SHARE").font(.system(size: 12, weight: .black)).foregroundColor(.white.opacity(0.4)).kerning(1.2)
                    Spacer()
                    Text("\(formatNumber(totalEnrollment)) Total")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue.opacity(0.6))
                }
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    let maxEnroll = carrierEnrollments.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(carrierEnrollments.enumerated()), id: \.element.id) { index, item in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("#\(index + 1) \(item.carrier)").font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(compactFormat(item.enrollment)).font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(.white)
                                        Text(String(format: "%.1f%%", Double(item.enrollment) / Double(totalEnrollment) * 100)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
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
    
    var chartDomain: ClosedRange<Int> {
        let enrollments = trendData.map { $0.enrollment }
        let minValue = enrollments.min() ?? 0
        let maxValue = enrollments.max() ?? 1000
        let rangeVal = maxValue - minValue
        let padding = rangeVal > 0 ? Double(rangeVal) * 0.2 : Double(maxValue) * 0.1
        let finalMin = Swift.max(0, Int(Double(minValue) - padding))
        let finalMax = Int(Double(maxValue) + padding)
        return finalMin...finalMax
    }
    
    func growthMetric(title: String, current: Int, prior: Int?) -> some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) GROWTH").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                Text(growthString(current: current, prior: prior))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(growthColor(current: current, prior: prior))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    func compactFormat(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000) }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000) }
        return "\(n)"
    }
    
    func growthString(current: Int, prior: Int?) -> String {
        guard let prior = prior, prior > 0 else { return "--" }
        let diff = current - prior
        let pct = (Double(diff) / Double(prior)) * 100.0
        return String(format: "%@%.1f%%", diff >= 0 ? "+" : "", pct)
    }
    
    func growthColor(current: Int, prior: Int?) -> Color {
        guard let prior = prior, prior > 0 else { return .gray }
        return current >= prior ? .green : .red
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
                    if self.selectedPeriod == nil { self.selectedPeriod = findClosestToToday(periods) }
                    fetchData()
                }
            } catch { print("Periods failed: \(error)") }
        }
    }
    
    func findClosestToToday(_ periods: [Period]) -> Period? {
        guard !periods.isEmpty else { return nil }
        let now = Date(); let calendar = Calendar.current
        let cy = calendar.component(.year, from: now); let cm = calendar.component(.month, from: now)
        return periods.min(by: { abs(($0.year * 12 + $0.month) - (cy * 12 + cm)) < abs(($1.year * 12 + $1.month) - (cy * 12 + cm)) })
    }
    
    func fetchFilterOptions() {
        Task {
            do {
                let stateRows = try dataStore.database.query(sql: "SELECT DISTINCT state FROM county_dim WHERE state != '' ORDER BY state")
                let states = stateRows.compactMap { $0["state"] as? String }
                
                // Exclude SNP-specific types from the general Plan Type filter
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
                let whereClause = conds.isEmpty ? "" : " WHERE " + conds.joined(separator: " AND ")
                let wherePeriod = " WHERE e.period_id = \(period.id)" + andClause

                let totalRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id \(wherePeriod)")
                let total = totalRow.first?["total"] as? Int ?? 0
                
                let pm = period.month == 1 ? 12 : period.month - 1; let py = period.month == 1 ? period.year - 1 : period.year
                let pmRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE pe.year = \(py) AND pe.month = \(pm) \(andClause)")
                let pmTotal = pmRow.first?["total"] as? Int
                
                let pdRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id WHERE pe.year = \(period.year - 1) AND pe.month = 12 \(andClause)")
                let pdTotal = pdRow.first?["total"] as? Int
                
                let trendRows = try dataStore.database.query(sql: "SELECT pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id JOIN periods pe ON e.period_id = pe.period_id \(whereClause) GROUP BY pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC")
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }

                let carrierRows = try dataStore.database.query(sql: "SELECT c.name as carrier, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id \(wherePeriod) GROUP BY c.carrier_id ORDER BY total DESC LIMIT 20")
                let carriers = carrierRows.map { EnrollmentByCarrier(carrier: $0["carrier"] as? String ?? "Unknown", enrollment: $0["total"] as? Int ?? 0) }
                
                let countyRows = try dataStore.database.query(sql: "SELECT co.name as county, p.name as plan, e.enrollment FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id \(wherePeriod) ORDER BY e.enrollment DESC LIMIT 50")
                let counties = countyRows.map { EnrollmentByCountyByPlan(county: $0["county"] as? String ?? "Unknown", plan: $0["plan"] as? String ?? "Unknown", enrollment: $0["enrollment"] as? Int ?? 0) }
                
                await MainActor.run {
                    self.totalEnrollment = total; self.priorMonthEnrollment = pmTotal; self.priorDecEnrollment = pdTotal
                    self.trendData = trend; self.carrierEnrollments = carriers; self.countyEnrollments = counties
                    self.isLoading = false
                }
            } catch { print("Fetch failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
}

struct FilterOverlay: View {
    @Binding var filter: DashboardFilter
    let availableStates: [String]
    let availablePlanTypes: [String]
    @Binding var isPresented: Bool
    let onApply: () -> Void
    
    @State private var draft: DashboardFilter
    
    init(filter: Binding<DashboardFilter>, availableStates: [String], availablePlanTypes: [String], isPresented: Binding<Bool>, onApply: @escaping () -> Void) {
        self._filter = filter
        self._draft = State(initialValue: filter.wrappedValue)
        self.availableStates = availableStates
        self.availablePlanTypes = availablePlanTypes
        self._isPresented = isPresented
        self.onApply = onApply
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.2)).frame(width: 40, height: 6).padding(.top, 10).padding(.bottom, 10)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Market Filters")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button("Reset") { withAnimation(.spring()) { draft = DashboardFilter() } }
                        .foregroundColor(.red)
                    
                    Button(action: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }) {
                        Label("Close", systemImage: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white.opacity(0.14))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal).padding(.bottom, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        filterSection(title: "Geography") {
                            Menu {
                                Button("All States") { draft.state = nil }
                                ForEach(availableStates, id: \.self) { s in Button(s) { draft.state = s } }
                            } label: {
                                HStack { Text(draft.state ?? "All States"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                            }
                        }
                        
                        filterSection(title: "Plan Attributes") {
                            VStack(spacing: 20) {
                                Menu {
                                    Button("All Types") { draft.planType = nil }
                                    ForEach(availablePlanTypes, id: \.self) { t in Button(t) { draft.planType = t } }
                                } label: {
                                    HStack { Text(draft.planType ?? "All Plan Types"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                    .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                                }
                                
                                filterToggle(title: "EGWP", selection: $draft.egwp)
                                filterToggle(title: "SNP", selection: $draft.snp)
                                
                                if draft.snp == "Yes" {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("SNP SUB-TYPES").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                                        HStack(spacing: 12) {
                                            Toggle("D-SNP", isOn: $draft.dsnp).toggleStyle(FilterChipStyle())
                                            Toggle("C-SNP", isOn: $draft.csnp).toggleStyle(FilterChipStyle())
                                            Toggle("I-SNP", isOn: $draft.isnp).toggleStyle(FilterChipStyle())
                                        }
                                    }
                                    .padding(.top, 8).transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false }
                            }) {
                                Label("Close", systemImage: "xmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.16), lineWidth: 1))
                            }
                            
                            Button(action: {
                                filter = draft; onApply()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false }
                            }) {
                                Text("Apply Filters")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding().padding(.bottom, 40)
                }
                .background(AppColors.background)
            }
            .background(AppColors.background)
            .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: -10)
        }
    }
    
    func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(size: 11, weight: .black)).foregroundColor(.white.opacity(0.4)).kerning(1.2)
            content()
        }
    }
    
    func filterToggle(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Spacer()
            Picker(title, selection: selection) {
                Text("All").tag("All")
                Text("Yes").tag("Yes")
                Text("No").tag("No")
            }
            .pickerStyle(.segmented).frame(width: 160)
        }
    }
}

struct FilterChipStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { configuration.isOn.toggle() } }) {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(configuration.isOn ? Color.blue : Color.white.opacity(0.05))
                .foregroundColor(.white).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: configuration.isOn ? 0 : 1))
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
