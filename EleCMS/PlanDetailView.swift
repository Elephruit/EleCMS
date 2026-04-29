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

            planDetailsSection(details)
                .padding(.horizontal)
            
            trendAndMapSection
                .padding(.horizontal)

            topCountiesSection
                .padding(.horizontal)
        }
    }

    var trendAndMapSection: some View {
        HStack(alignment: .top, spacing: 16) {
            MarketTrendChart(
                trendData: trendData,
                rawSelectedDate: .constant(nil),
                chartDomain: chartDomain,
                chartHeight: 340
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Service Area Footprint", subtitle: "\(serviceAreaCountyCount) Counties Offered")

                ModernCard {
                    CountyMapView(footprintFIPS: footprintFIPS, footprintCounties: footprintCounties, states: footprintStates)
                        .id(selectedPlanID ?? "")
                        .frame(height: 340)
                        .cornerRadius(12)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    var topCountiesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Top Counties by Enrollment")

            ModernCard {
                VStack(alignment: .leading, spacing: 12) {
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

    func planDetailsSection(_ details: PlanDetailData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomSectionHeader(title: "Plan Details", subtitle: "Landscape benefits and cost fields")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                detailTile(label: "Premium", value: currency(details.premium), icon: "dollarsign.circle")
                detailTile(label: "Deductible", value: currency(details.deductible), icon: "creditcard")
                detailTile(label: "Part C Premium", value: currency(details.partCPremium), icon: "cross.case")
                detailTile(label: "Part D Total Premium", value: currency(details.partDTotalPremium), icon: "pills")
                detailTile(label: "Part D Deductible", value: currency(details.partDDeductible), icon: "creditcard")
                detailTile(label: "MOOP", value: currency(details.moopAmount), icon: "shield")
                detailTile(label: "Part D OOP Threshold", value: currency(details.oopThreshold), icon: "chart.line.uptrend.xyaxis")
                detailTile(label: "Part D Coverage", value: textValue(details.partDCoverage), icon: "checkmark.seal")
                detailTile(label: "Drug Benefit", value: [details.drugBenefitCategory, details.drugBenefitType].compactMap { cleanText($0) }.joined(separator: " / "), icon: "list.bullet.clipboard")
                detailTile(label: "Basic Rx Premium", value: currency(details.partDBasicPremium), icon: "dollarsign")
                detailTile(label: "Supplemental Rx Premium", value: currency(details.partDSupplementalPremium), icon: "plus.circle")
                detailTile(label: "LIPS Subsidy", value: currency(details.lowIncomePremiumSubsidy), icon: "person.crop.circle.badge.checkmark")
                detailTile(label: "Part D LIPS CMS Pays", value: currency(details.partDLipsAmount), icon: "building.columns")
                detailTile(label: "Low-Income Premium", value: currency(details.partDLowIncomePremium), icon: "person.text.rectangle")
                detailTile(label: "No Part D Deductible Tier", value: textValue(details.noPartDDeductible), icon: "tag")
                detailTile(label: "Zero-Dollar Cost Share", value: textValue(details.zeroDollarCostSharing), icon: "0.circle")
                detailTile(label: "Overall Stars", value: rating(details.overallStarRating), icon: "star")
                detailTile(label: "Part C / D Stars", value: "\(rating(details.partCStarRating)) / \(rating(details.partDStarRating))", icon: "star.leadinghalf.filled")
            }
        }
    }

    func detailTile(label: String, value: String, icon: String) -> some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                    Text(label.uppercased())
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(value.isEmpty ? "N/A" : value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(minHeight: 36, alignment: .topLeading)
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
