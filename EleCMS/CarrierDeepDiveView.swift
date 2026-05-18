import SwiftUI
import Charts

struct CarrierDeepDiveView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    @Binding var selectedDestination: NavDestination
    
    @State private var selectedCarrier: String?
    @State private var availableCarriers: [CarrierOption] = []
    @State private var isCarrierPickerPresented = false
    @State private var carrierSearchText = ""
    
    @State private var selectedPeriod: Period?
    @State private var totalEnrollment: Int = 0
    @State private var stateBreakdown: [StateShare] = []
    @State private var typeBreakdown: [TypeShare] = []
    @State private var trendData: [TrendPoint] = []
    @State private var isLoading = false
    
    // Drill-down data
    @State private var expandedState: String? = nil
    @State private var expandedType: String? = nil
    @State private var stateBreakdowns: [String: GeographicBreakdown] = [:]
    
    struct StateShare: Identifiable {
        var id: String { state }
        let state: String
        let enrollment: Int
        let percentage: Double
    }
    
    struct TypeShare: Identifiable {
        var id: String { type }
        let type: String
        let enrollment: Int
    }
    
    struct CarrierOption: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let enrollment: Int
    }
    
    var body: some View {
        GeometryReader { mainGeo in
            ZStack(alignment: .top) {
                AppColors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    PageHeader(title: "Carrier Deep-dive", subtitle: selectedCarrier, isMenuOpen: $isMenuOpen)
                    
                    if availableCarriers.isEmpty {
                        VStack(spacing: 20) {
                            ProgressView().tint(.white)
                            Text("Analyzing Carriers...").foregroundColor(.gray)
                        }
                        .padding(.top, 100)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 32) {
                                carrierSelector
                                
                                if let carrier = selectedCarrier {
                                    carrierContent(for: carrier)
                                } else {
                                    selectCarrierPrompt
                                }
                            }
                            .padding(.vertical, 24)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                
                if isLoading {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
                
                if isCarrierPickerPresented {
                    CarrierPickerSheet(
                        carriers: availableCarriers,
                        selectedCarrier: selectedCarrier,
                        searchText: $carrierSearchText,
                        isPresented: $isCarrierPickerPresented,
                        screenSize: mainGeo.size,
                        onSelect: { carrier in
                            selectedCarrier = carrier.name
                            fetchCarrierData(carrier: carrier.name)
                        }
                    )
                    .zIndex(100)
                }
            }
        }
        .onAppear { fetchAvailableCarriers() }
    }
    
    var carrierSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT CARRIER")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.white.opacity(0.4))
                .kerning(1.2)
                .padding(.horizontal)
            
            Button(action: {
                carrierSearchText = ""
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isCarrierPickerPresented = true
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
                        Text(selectedCarrier ?? "Select Carrier")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let carrier = selectedCarrierOption {
                            Text("\(UIFormatter.compactFormat(carrier.enrollment)) latest enrollment")
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text("Search top carriers by latest enrollment")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(16)
                .background(AppColors.surface)
                .cornerRadius(18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }
    
    var selectedCarrierOption: CarrierOption? {
        guard let selectedCarrier else { return nil }
        return availableCarriers.first { $0.name == selectedCarrier }
    }
    
    @ViewBuilder
    func carrierContent(for carrier: String) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // High-level Stats
            EnrollmentMetricCard(title: "Total Enrollment", enrollment: totalEnrollment)
                .padding(.horizontal)
            
            // Trend Chart
            if trendData.count > 1 {
                VStack(alignment: .leading, spacing: 16) {
                    CustomSectionHeader(title: "Growth Trend")
                    
                    ModernCard {
                        Chart {
                            ForEach(trendData) { point in
                                LineMark(x: .value("Month", point.date), y: .value("Enrollment", point.enrollment))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                    .lineStyle(StrokeStyle(lineWidth: 3))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                                AxisValueLabel {
                                    if let intVal = value.as(Int.self) {
                                        Text(UIFormatter.compactFormat(intVal))
                                    }
                                }
                            }
                        }
                        .frame(height: 180)
                    }
                    .padding(.horizontal)
                }
            }
            
            // Geographic Footprint
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Geographic Footprint", subtitle: "Tap a state to drill-down")
                
                VStack(spacing: 12) {
                    let maxVal = stateBreakdown.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(stateBreakdown.enumerated()), id: \.element.id) { index, share in
                        stateRow(index: index, share: share, maxVal: maxVal)
                    }
                }
                .padding(.horizontal)
            }
            
            // Business Mix
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Business Mix")
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(typeBreakdown) { type in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(type.type.uppercased()).font(.system(size: 8, weight: .black)).foregroundColor(.blue)
                                Text(UIFormatter.compactFormat(type.enrollment)).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                Text(String(format: "%.1f%%", Double(type.enrollment) / Double(totalEnrollment) * 100)).font(.system(size: 10)).foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    func stateRow(index: Int, share: StateShare, maxVal: Int) -> some View {
        let isExpanded = expandedState == share.state
        
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if isExpanded { expandedState = nil; expandedType = nil }
                    else { expandedState = share.state; fetchStateBreakdown(share.state, enrollment: share.enrollment) }
                }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("#\(index + 1) \(share.state)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(UIFormatter.compactFormat(share.enrollment)).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                            Text(String(format: "%.1f%% of book", share.percentage)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * CGFloat(share.enrollment) / CGFloat(maxVal), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding()
                .background(AppColors.surface)
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isExpanded ? Color.blue.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                if let breakdown = stateBreakdowns[share.state] {
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
                        Text(String(format: "%.1f%% of carrier in state", type.shareOfTotal * 100)).font(.system(size: 9)).foregroundColor(.gray)
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
            Text(label).font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
            Text("\(diff >= 0 ? "+" : "")\(UIFormatter.compactFormat(diff))").font(.system(size: 14, weight: .bold)).foregroundColor(diff >= 0 ? .green : .red)
            Text(String(format: "(%.1f%%)", pct)).font(.system(size: 14)).foregroundColor(diff >= 0 ? .green : .red)
        }
    }
    
    var selectCarrierPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Select a Carrier").font(.headline).foregroundColor(.white)
            Text("Search or choose a top carrier to analyze market performance and business mix.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    func fetchAvailableCarriers() {
        Task {
            do {
                let rows = try dataStore.database.query(sql: """
                    WITH latest_period AS (
                        SELECT period_id
                        FROM periods
                        ORDER BY year DESC, month DESC
                        LIMIT 1
                    )
                    SELECT c.name, COALESCE(SUM(e.enrollment), 0) as total
                    FROM carrier_dim c
                    LEFT JOIN plan_dim p ON p.carrier_id = c.carrier_id
                    LEFT JOIN enrollment_records e ON e.plan_id = p.plan_id
                        AND e.period_id = (SELECT period_id FROM latest_period)
                    GROUP BY c.carrier_id, c.name
                    ORDER BY total DESC, c.name ASC
                """)
                let carriers = rows.compactMap { row -> CarrierOption? in
                    guard let name = row["name"] as? String else { return nil }
                    return CarrierOption(name: name, enrollment: row["total"] as? Int ?? 0)
                }
                await MainActor.run { self.availableCarriers = carriers }
            } catch { print("Carriers failed: \(error)") }
        }
    }
    
    func fetchCarrierData(carrier: String) {
        isLoading = true
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id, year, month FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let currentPeriod = pRow.first.map({ Period(id: $0["period_id"] as? Int ?? 0, year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0) }) else {
                    await MainActor.run { self.isLoading = false }
                    return
                }
                
                let pid = currentPeriod.id
                
                let totalRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id WHERE c.name = ? AND e.period_id = ?", arguments: [carrier, pid])
                let total = totalRow.first?["total"] as? Int ?? 0
                
                let stateRows = try dataStore.database.query(sql: "SELECT co.state, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id WHERE c.name = ? AND e.period_id = ? GROUP BY co.state ORDER BY total DESC", arguments: [carrier, pid])
                let states = stateRows.map {
                    let enrollment = $0["total"] as? Int ?? 0
                    let percentage = total > 0 ? Double(enrollment) / Double(total) * 100 : 0
                    return StateShare(state: $0["state"] as? String ?? "??", enrollment: enrollment, percentage: percentage)
                }
                
                let typeRows = try dataStore.database.query(sql: """
                    SELECT 
                        CASE 
                            WHEN p.type LIKE '%PDP%' THEN 'PDP'
                            WHEN p.is_snp = 1 THEN 'SNP'
                            WHEN p.is_egwp = 1 THEN 'EGWP'
                            ELSE 'MA-Only/Other'
                        END as mix_type,
                        SUM(e.enrollment) as total
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    WHERE c.name = ? AND e.period_id = ?
                    GROUP BY mix_type
                    ORDER BY total DESC
                """, arguments: [carrier, pid])
                let mix = typeRows.map { TypeShare(type: $0["mix_type"] as? String ?? "Other", enrollment: $0["total"] as? Int ?? 0) }
                
                let trendRows = try dataStore.database.query(sql: "SELECT pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN periods pe ON e.period_id = pe.period_id WHERE c.name = ? GROUP BY pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC", arguments: [carrier])
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }
                
                await MainActor.run {
                    self.selectedPeriod = currentPeriod
                    self.totalEnrollment = total
                    self.stateBreakdown = states
                    self.typeBreakdown = mix
                    self.trendData = trend
                    self.isLoading = false
                    
                    self.expandedState = nil
                    self.expandedType = nil
                    self.stateBreakdowns.removeAll()
                }
            } catch { print("Carrier data failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }

    func fetchStateBreakdown(_ state: String, enrollment: Int) {
        guard let period = selectedPeriod, let carrier = selectedCarrier else { return }
        Task {
            do {
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
                    WHERE co.state = ? 
                      AND c.name = ?
                      AND e.period_id IN (\(period.id), \(pmID ?? -1), \(pyID ?? -1))
                    GROUP BY p.type, p.plan_id
                """
                
                let rows = try dataStore.database.query(sql: sql, arguments: [state, carrier])
                
                var typeMap: [String: ProductTypeBreakdown] = [:]
                let carrierTotal = Double(enrollment)
                
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
                        shareOfTotal: carrierTotal > 0 ? Double(curE) / carrierTotal : 0
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
                        shareOfTotal: carrierTotal > 0 ? Double(totalE) / carrierTotal : 0,
                        plans: type.plans.sorted(by: { $0.enrollment > $1.enrollment })
                    )
                }.sorted(by: { $0.enrollment > $1.enrollment })
                
                await MainActor.run {
                    self.stateBreakdowns[state] = GeographicBreakdown(id: state, enrollment: enrollment, types: sortedTypes)
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
}

struct CarrierPickerSheet: View {
    let carriers: [CarrierDeepDiveView.CarrierOption]
    let selectedCarrier: String?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let screenSize: CGSize
    let onSelect: (CarrierDeepDiveView.CarrierOption) -> Void
    
    private var filteredCarriers: [CarrierDeepDiveView.CarrierOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return carriers }
        return carriers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { close() }
            
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 6)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select Carrier")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(searchText.isEmpty ? "Top carriers by latest enrollment" : "\(filteredCarriers.count) matching carriers")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.gray)
                    
                    TextField("Search carriers", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if filteredCarriers.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 38, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.6))
                                Text("No Carriers Found")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Try a shorter name or clear the search.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else {
                            ForEach(filteredCarriers) { carrier in
                                Button(action: {
                                    onSelect(carrier)
                                    close()
                                }) {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedCarrier == carrier.name ? Color.blue.opacity(0.22) : Color.white.opacity(0.06))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: selectedCarrier == carrier.name ? "checkmark" : "building.2")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundColor(selectedCarrier == carrier.name ? .blue : .gray)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(carrier.name)
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            
                                            Text("\(UIFormatter.compactFormat(carrier.enrollment)) latest enrollment")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .padding(14)
                                    .background(AppColors.surface)
                                    .cornerRadius(16)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColors.background)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func close() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}
