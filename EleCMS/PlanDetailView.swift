import SwiftUI
import Charts
import MapKit

struct PlanDetailView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    let initialPlanID: String? // contractID-planID
    let onBack: (() -> Void)?
    
    @State private var selectedPlanID: String?
    @State private var planDetails: PlanDetailData?
    @State private var availablePlans: [PlanOption] = []
    @State private var isPlanPickerPresented = false
    @State private var planSearchText = ""
    @State private var isLoading = false
    @State private var planDataRequestID = UUID()
    
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
        let partDDeductible: Double?
        let partCPremium: Double?
        let partDBasicPremium: Double?
        let partDSupplementalPremium: Double?
        let partDTotalPremium: Double?
        let lowIncomePremiumSubsidy: Double?
        let partDLipsAmount: Double?
        let partDLowIncomePremium: Double?
        let oopThreshold: Double?
        let moopAmount: Double?
        let partDCoverage: String?
        let drugBenefitCategory: String?
        let drugBenefitType: String?
        let zeroDollarCostSharing: String?
        let noPartDDeductible: String?
        let partCStarRating: Double?
        let partDStarRating: Double?
        let overallStarRating: Double?
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
    @State private var footprintCounties: Set<CountyMapCounty> = []
    @State private var footprintStates: Set<String> = []
    
    init(dataStore: DataStore, isMenuOpen: Binding<Bool>, planID: String? = nil, onBack: (() -> Void)? = nil) {
        self.dataStore = dataStore
        self._isMenuOpen = isMenuOpen
        self.initialPlanID = planID
        self.onBack = onBack
    }
    
    var body: some View {
        GeometryReader { mainGeo in
            ZStack(alignment: .top) {
                AppColors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    PageHeader(
                        title: "Plan Deep-dive",
                        subtitle: planDetails?.name ?? selectedPlanID,
                        isMenuOpen: $isMenuOpen,
                        rightButton: onBack != nil ? AnyView(
                            Button(action: { onBack?() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                                    Text("Back").font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                            }
                        ) : nil
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
                            resetPlanData()
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
                resetPlanData()
                fetchPlanData(planID: pid)
            }
        }
        .onChange(of: planSearchText) { _ in
            fetchAvailablePlans(query: planSearchText)
        }
    }
    
    var planSelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Select Plan")
            
            Button(action: {
                planSearchText = ""
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isPlanPickerPresented = true
                }
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.blue, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planDetails?.name ?? "Search Plans")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let details = planDetails {
                            Text("\(details.contractID)-\(details.planID) • \(details.carrier)")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                        } else {
                            Text("Search by Name, Contract, or ID").font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                }
                .padding(16)
                .background(AppColors.surface)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain).padding(.horizontal)
        }
    }

    
    @ViewBuilder
    func planContent(_ details: PlanDetailData) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Hero Stats & Summary
            HStack(alignment: .top, spacing: 24) {
                HeroMetricCard(
                    title: "Total Enrollment",
                    value: UIFormatter.formatNumber(details.enrollment),
                    momDiff: details.momDiff,
                    momPct: details.momPct,
                    ytdDiff: details.yoyDiff,
                    ytdPct: details.yoyPct
                )
                
                VStack(alignment: .leading, spacing: 20) {
                    summaryItem(label: "Monthly Premium", value: currency(details.premium), icon: "dollarsign.circle.fill", color: .blue)
                    summaryItem(label: "Plan Type", value: details.type, icon: "tag.fill", color: .purple)
                }
                .padding(24)
                .frame(width: 240, height: 180, alignment: .topLeading)
                .background(AppColors.surface)
                .cornerRadius(24)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .padding(.horizontal)

            planDetailsSection(details)
                .padding(.horizontal)
            
            trendAndMapSection
                .padding(.horizontal)

            topCountiesSection
                .padding(.horizontal)
        }
    }

    func summaryItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
                Text(label.uppercased()).font(.system(size: 10, weight: .black)).foregroundColor(.gray).kerning(0.5)
            }
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white).lineLimit(1)
        }
    }

    var trendAndMapSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Enrollment Trend")
                ModernCard {
                    Chart {
                        ForEach(trendData) { point in
                            AreaMark(x: .value("Date", point.date), y: .value("Enrollment", point.enrollment))
                                .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            
                            LineMark(x: .value("Date", point.date), y: .value("Enrollment", point.enrollment))
                                .foregroundStyle(.blue)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                        }
                    }
                    .chartYScale(domain: chartDomain)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                            AxisValueLabel { if let intVal = value.as(Int.self) { Text(UIFormatter.compactFormat(intVal)).font(.system(size: 10)) } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel { if let date = value.as(Date.self) { Text(date, format: .dateTime.month(.abbreviated)).font(.system(size: 10)) } }
                        }
                    }
                    .frame(height: 300)
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Service Area Footprint", subtitle: "\(serviceAreaCountyCount) Counties Offered")

                ModernCard {
                    CountyMapView(footprintFIPS: footprintFIPS, footprintCounties: footprintCounties, states: footprintStates)
                        .id(selectedPlanID ?? "")
                        .frame(height: 300)
                        .cornerRadius(12)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    var topCountiesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Top Counties by Enrollment")

            HStack(spacing: 16) {
                ForEach(countyEnrollments.prefix(4)) { ce in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(ce.id).font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text(ce.state).font(.system(size: 10, weight: .black)).foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(UIFormatter.formatNumber(ce.enrollment))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("Enrolled").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surface)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
        }
    }


    func planDetailsSection(_ details: PlanDetailData) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            CustomSectionHeader(title: "Plan Architecture", subtitle: "Structured Benefits & Metrics")

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    DataPanel(title: "Financial Summary", icon: "dollarsign.circle.fill") {
                        DataRow(label: "Monthly Premium", value: currency(details.premium))
                        DataRow(label: "Medical Deductible", value: currency(details.deductible))
                        DataRow(label: "MOOP Amount", value: currency(details.moopAmount))
                        DataRow(label: "Part C Premium", value: currency(details.partCPremium), isLast: true)
                    }
                    
                    DataPanel(title: "Quality & Ratings", icon: "star.fill") {
                        RatingStarsRow(label: "Overall Rating", rating: details.overallStarRating)
                        RatingStarsRow(label: "Part C Rating", rating: details.partCStarRating)
                        RatingStarsRow(label: "Part D Rating", rating: details.partDStarRating, isLast: true)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    DataPanel(title: "Drug & Pharmacy", icon: "pills.fill") {
                        DataRow(label: "Part D Total Premium", value: currency(details.partDTotalPremium))
                        DataRow(label: "Part D Deductible", value: currency(details.partDDeductible))
                        DataRow(label: "Part D OOP Threshold", value: currency(details.oopThreshold))
                        DataRow(label: "Part D Coverage", value: textValue(details.partDCoverage))
                        DataRow(label: "Drug Benefit", value: [details.drugBenefitCategory, details.drugBenefitType].compactMap { cleanText($0) }.joined(separator: " / "))
                        DataRow(label: "LIPS Subsidy", value: currency(details.lowIncomePremiumSubsidy))
                        DataRow(label: "LIPS CMS Pays", value: currency(details.partDLipsAmount))
                        DataRow(label: "Low-Income Premium", value: currency(details.partDLowIncomePremium))
                        DataRow(label: "Zero-Dollar Cost Share", value: textValue(details.zeroDollarCostSharing))
                        DataRow(label: "No Part D Ded Tier", value: textValue(details.noPartDDeductible), isLast: true)
                    }
                }
                .frame(maxWidth: .infinity)
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

    var serviceAreaCountyCount: Int {
        Swift.max(footprintCounties.count, footprintFIPS.count)
    }

    func currency(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "$%.2f", value)
    }

    func rating(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.1f", value)
    }

    func textValue(_ value: String?) -> String {
        cleanText(value) ?? "N/A"
    }

    func cleanText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.localizedCaseInsensitiveCompare("Not Applicable") != .orderedSame else {
            return nil
        }
        return trimmed
    }
    
    var selectPlanPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 60)).foregroundColor(.gray.opacity(0.5))
            Text("Select a Plan").font(.headline).foregroundColor(.white)
            Text("Enter a Plan ID or name to view detailed enrollment trends, premiums, and geographic footprint.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }
    
    func fetchAvailablePlans(query: String? = nil) {
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let pid = pRow.first?["period_id"] as? Int else { return }
                
                var sql = """
                    SELECT p.contract_id, p.cms_plan_id, p.name, c.name as carrier, SUM(e.enrollment) as total
                    FROM plan_dim p
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    JOIN enrollment_records e ON e.plan_id = p.plan_id
                    WHERE e.period_id = \(pid)
                """

                var args: [Any] = []
                if let q = query, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sql += " AND (p.name LIKE ? OR p.contract_id LIKE ? OR p.cms_plan_id LIKE ? OR c.name LIKE ?)"
                    let searchArg = "%\(q)%"
                    args = [searchArg, searchArg, searchArg, searchArg]
                }

                sql += """
                    GROUP BY p.plan_id
                    ORDER BY total DESC
                    LIMIT 200
                """

                let rows = try dataStore.database.query(sql: sql, arguments: args)
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
        let requestID = UUID()
        planDataRequestID = requestID
        isLoading = true
        let parts = planID.split(separator: "-")
        guard parts.count == 2 else { isLoading = false; return }
        let contractID = String(parts[0])
        let cmsPlanID = String(parts[1])
        
        Task {
            do {
                let pRow = try dataStore.database.query(sql: "SELECT period_id, year, month FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let currentPeriod = pRow.first.map({ Period(id: $0["period_id"] as? Int ?? 0, year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0) }) else {
                    await MainActor.run {
                        guard self.planDataRequestID == requestID else { return }
                        self.isLoading = false
                    }
                    return
                }
                
                let pmID = try getPriorPeriodID(currentPeriod)
                let pyID = try getPriorYearPeriodID(currentPeriod)
                
                // 1. Basic Details
                let detailSQL = """
                    SELECT p.*, c.name as carrier_name,
                        l.monthly_premium,
                        l.deductible,
                        l.part_d_deductible,
                        l.part_c_premium,
                        l.part_d_basic_premium,
                        l.part_d_supplemental_premium,
                        l.part_d_total_premium,
                        l.low_income_premium_subsidy,
                        l.part_d_lips_amount,
                        l.part_d_low_income_premium,
                        l.oop_threshold,
                        l.moop_amount,
                        l.part_d_coverage,
                        l.drug_benefit_category,
                        l.drug_benefit_type,
                        l.zero_dollar_cost_sharing,
                        l.no_part_d_deductible,
                        l.part_c_star_rating,
                        l.part_d_star_rating,
                        l.overall_star_rating,
                        SUM(CASE WHEN e.period_id = \(currentPeriod.id) THEN e.enrollment ELSE 0 END) as cur_e,
                        SUM(CASE WHEN e.period_id = \(pmID ?? -1) THEN e.enrollment ELSE 0 END) as pm_e,
                        SUM(CASE WHEN e.period_id = \(pyID ?? -1) THEN e.enrollment ELSE 0 END) as py_e
                    FROM plan_dim p
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    LEFT JOIN landscape_records l ON l.plan_id = p.plan_id
                        AND l.year = COALESCE(
                            (SELECT MAX(year) FROM landscape_records WHERE plan_id = p.plan_id AND year <= \(currentPeriod.year)),
                            (SELECT MAX(year) FROM landscape_records WHERE plan_id = p.plan_id)
                        )
                    LEFT JOIN enrollment_records e ON e.plan_id = p.plan_id
                    WHERE p.contract_id = ? AND p.cms_plan_id = ?
                    GROUP BY p.plan_id
                """
                let details = try dataStore.database.query(sql: detailSQL, arguments: [contractID, cmsPlanID])
                guard let d = details.first else {
                    await MainActor.run {
                        guard self.planDataRequestID == requestID else { return }
                        self.isLoading = false
                    }
                    return
                }
                
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
                    partDDeductible: d["part_d_deductible"] as? Double,
                    partCPremium: d["part_c_premium"] as? Double,
                    partDBasicPremium: d["part_d_basic_premium"] as? Double,
                    partDSupplementalPremium: d["part_d_supplemental_premium"] as? Double,
                    partDTotalPremium: d["part_d_total_premium"] as? Double,
                    lowIncomePremiumSubsidy: d["low_income_premium_subsidy"] as? Double,
                    partDLipsAmount: d["part_d_lips_amount"] as? Double,
                    partDLowIncomePremium: d["part_d_low_income_premium"] as? Double,
                    oopThreshold: d["oop_threshold"] as? Double,
                    moopAmount: d["moop_amount"] as? Double,
                    partDCoverage: d["part_d_coverage"] as? String,
                    drugBenefitCategory: d["drug_benefit_category"] as? String,
                    drugBenefitType: d["drug_benefit_type"] as? String,
                    zeroDollarCostSharing: d["zero_dollar_cost_sharing"] as? String,
                    noPartDDeductible: d["no_part_d_deductible"] as? String,
                    partCStarRating: d["part_c_star_rating"] as? Double,
                    partDStarRating: d["part_d_star_rating"] as? Double,
                    overallStarRating: d["overall_star_rating"] as? Double,
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
                    AND psa.year = COALESCE(
                        (SELECT MAX(year) FROM plan_service_area WHERE plan_id = p.plan_id AND year <= \(currentPeriod.year)),
                        (SELECT MAX(year) FROM plan_service_area WHERE plan_id = p.plan_id)
                    )
                """, arguments: [contractID, cmsPlanID])
                
                let footprint = footprintRows.map { row in
                    let rawFips = row["fips_county_code"] as? String ?? ""
                    return PlanCountyEnrollment(
                        id: row["name"] as? String ?? "",
                        state: row["state"] as? String ?? "",
                        fips: normalizedFIPS(rawFips) ?? "",
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
                    return PlanCountyEnrollment(
                        id: row["name"] as? String ?? "",
                        state: row["state"] as? String ?? "",
                        fips: normalizedFIPS(rawFips) ?? "",
                        enrollment: row["enrollment"] as? Int ?? 0
                    )
                }
                
                var fipsSet = Set(footprint.compactMap { $0.fips.isEmpty ? nil : $0.fips })
                var countySet = Set(footprint.compactMap { countyMapCounty(from: $0) })
                if fipsSet.isEmpty {
                    // Fallback to enrollment counties if footprint is empty
                    fipsSet = Set(enrollmentCounties.compactMap { $0.fips.isEmpty ? nil : $0.fips })
                }
                if countySet.isEmpty {
                    countySet = Set(enrollmentCounties.compactMap { countyMapCounty(from: $0) })
                }
                
                let allStates = Set(footprint.map { $0.state })
                    .union(Set(enrollmentCounties.map { $0.state }))
                    .filter { !$0.isEmpty && $0 != "??" }
                
                await MainActor.run {
                    guard self.planDataRequestID == requestID, self.selectedPlanID == planID else { return }
                    self.planDetails = detailData
                    self.trendData = trend
                    self.countyEnrollments = enrollmentCounties
                    self.footprintFIPS = fipsSet
                    self.footprintCounties = countySet
                    self.footprintStates = allStates
                    self.isLoading = false
                }
            } catch {
                print("Plan data failed: \(error)")
                await MainActor.run {
                    guard self.planDataRequestID == requestID else { return }
                    self.isLoading = false
                }
            }
        }
    }

    private func resetPlanData() {
        planDetails = nil
        trendData = []
        countyEnrollments = []
        footprintFIPS = []
        footprintCounties = []
        footprintStates = []
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

    private func normalizedFIPS(_ value: String) -> String? {
        let digits = String(value.filter { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(5)).leftPadding(toLength: 5, withPad: "0")
    }

    private func countyMapCounty(from county: PlanCountyEnrollment) -> CountyMapCounty? {
        let name = county.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = county.state.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !state.isEmpty, state != "??", name.localizedCaseInsensitiveCompare("All Counties") != .orderedSame else {
            return nil
        }
        return CountyMapCounty(state: state, name: name)
    }
}

// MARK: - Sub-components

struct DataPanel<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(.blue)
                Text(title.uppercased()).font(.system(size: 12, weight: .black)).foregroundColor(.white).kerning(1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.03))
            
            Divider().background(Color.white.opacity(0.1))
            
            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 8)
        }
        .background(AppColors.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct DataRow: View {
    let label: String
    let value: String
    var isLast: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                Spacer()
                Text(value.isEmpty ? "N/A" : value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            if !isLast {
                Divider().padding(.horizontal, 20).background(Color.white.opacity(0.05))
            }
        }
    }
}

struct RatingStarsRow: View {
    let label: String
    let rating: Double?
    var isLast: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    if let r = rating {
                        Text(String(format: "%.1f", r)).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white).padding(.trailing, 4)
                        ForEach(0..<5) { index in
                            starImage(for: Double(index), rating: r)
                                .font(.system(size: 10))
                                .foregroundColor(Double(index) < r ? .yellow : .gray.opacity(0.3))
                        }
                    } else {
                        Text("N/A").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            if !isLast {
                Divider().padding(.horizontal, 20).background(Color.white.opacity(0.05))
            }
        }
    }
    
    func starImage(for index: Double, rating: Double) -> Image {
        if index + 1 <= rating {
            return Image(systemName: "star.fill")
        } else if index < rating {
            return Image(systemName: "star.leadinghalf.filled")
        } else {
            return Image(systemName: "star")
        }
    }
}

struct HeroMetricCard: View {
    let title: String
    let value: String
    let momDiff: Int
    let momPct: Double
    let ytdDiff: Int
    let ytdPct: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.blue.opacity(0.8))
                    .kerning(1.0)
                Text(value)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 24) {
                growthMetric(label: "MoM", diff: momDiff, pct: momPct)
                growthMetric(label: "YTD", diff: ytdDiff, pct: ytdPct)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading)
        .background(
            ZStack {
                AppColors.surface
                LinearGradient(colors: [.blue.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
    
    private func growthMetric(label: String, diff: Int, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            HStack(spacing: 4) {
                Image(systemName: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(diff >= 0 ? "+" : "")\(UIFormatter.formatNumber(diff))")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text(String(format: "(%.1f%%)", pct))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(diff >= 0 ? .green : .red)
        }
    }
}


private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(character), count: toLength - count) + self
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
        ZStack(alignment: .top) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColors.background)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func close() { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false } }
}
