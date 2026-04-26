import SwiftUI

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

struct DashboardView: View {
    let dataStore: DataStore
    
    @State private var countyEnrollments: [EnrollmentByCountyByPlan] = []
    @State private var carrierEnrollments: [EnrollmentByCarrier] = []
    @State private var availablePeriods: [Period] = []
    @State private var selectedPeriod: Period?
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()
                
                LinearGradient(colors: [AppColors.gradientStart.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Header & Period Picker
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Market Analysis")
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Enrollment by Carrier & Geography")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                                Spacer()
                                Button(action: fetchData) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                                }
                            }
                            
                            if !availablePeriods.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(availablePeriods) { period in
                                            Button(action: {
                                                selectedPeriod = period
                                                fetchData()
                                            }) {
                                                Text(period.shortName)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .padding(.vertical, 8)
                                                    .padding(.horizontal, 16)
                                                    .background(selectedPeriod?.id == period.id ? Color.blue : AppColors.surface)
                                                    .foregroundColor(.white)
                                                    .cornerRadius(12)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                                    )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        if carrierEnrollments.isEmpty && countyEnrollments.isEmpty {
                            VStack(spacing: 24) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.linearGradient(colors: [.gray, .clear], startPoint: .top, endPoint: .bottom))
                                Text("No Data Records Found")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Select a period in the Data tab to begin analyzing market distribution.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                        } else {
                            // Carrier Metrics (Vertical)
                            VStack(alignment: .leading, spacing: 16) {
                                Text("CARRIER MARKET SHARE")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundColor(.white.opacity(0.4))
                                    .kerning(1.2)
                                    .padding(.horizontal)
                                
                                VStack(spacing: 16) {
                                    let maxEnrollment = carrierEnrollments.map { $0.enrollment }.max() ?? 1
                                    ForEach(carrierEnrollments) { item in
                                        ModernCard {
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    Text(item.carrier)
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    Text("\(item.enrollment)")
                                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                                        .foregroundColor(.white)
                                                }
                                                
                                                // Mini Bar Chart
                                                GeometryReader { geo in
                                                    ZStack(alignment: .leading) {
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(Color.white.opacity(0.05))
                                                            .frame(height: 8)
                                                        
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                                            .frame(width: geo.size.width * CGFloat(item.enrollment) / CGFloat(maxEnrollment), height: 8)
                                                    }
                                                }
                                                .frame(height: 8)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // County Distribution
                            VStack(alignment: .leading, spacing: 16) {
                                Text("TOP COUNTY ENROLLMENTS")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundColor(.white.opacity(0.4))
                                    .kerning(1.2)
                                    .padding(.horizontal)
                                
                                VStack(spacing: 1) {
                                    ForEach(countyEnrollments) { item in
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.plan)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Text(item.county.uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.gray)
                                            }
                                            Spacer()
                                            Text("\(item.enrollment)")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                        .padding()
                                        .background(AppColors.surface.opacity(0.5))
                                    }
                                }
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                fetchPeriods()
            }
        }
    }
    
    func fetchPeriods() {
        Task {
            do {
                let rows = try dataStore.database.query(sql: "SELECT period_id, year, month FROM periods ORDER BY year DESC, month DESC")
                let periods = rows.map { row in
                    Period(id: row["period_id"] as? Int ?? 0, year: row["year"] as? Int ?? 0, month: row["month"] as? Int ?? 0)
                }
                
                await MainActor.run {
                    self.availablePeriods = periods
                    if self.selectedPeriod == nil {
                        self.selectedPeriod = findClosestToToday(periods)
                    }
                    fetchData()
                }
            } catch {
                print("Failed to fetch periods: \(error)")
            }
        }
    }
    
    func findClosestToToday(_ periods: [Period]) -> Period? {
        guard !periods.isEmpty else { return nil }
        
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        return periods.min(by: { p1, p2 in
            let d1 = abs((p1.year * 12 + p1.month) - (currentYear * 12 + currentMonth))
            let d2 = abs((p2.year * 12 + p2.month) - (currentYear * 12 + currentMonth))
            return d1 < d2
        })
    }
    
    func fetchData() {
        guard let periodID = selectedPeriod?.id else { return }
        isLoading = true
        Task {
            do {
                let carriersSQL = """
                    SELECT c.name as carrier, SUM(e.enrollment) as total
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN carrier_dim c ON c.carrier_id = p.carrier_id
                    WHERE e.period_id = \(periodID)
                    GROUP BY c.carrier_id
                    ORDER BY total DESC
                    LIMIT 20
                """
                let carrierRows = try dataStore.database.query(sql: carriersSQL)
                let carriers = carrierRows.map { row in
                    EnrollmentByCarrier(carrier: row["carrier"] as? String ?? "Unknown", enrollment: row["total"] as? Int ?? 0)
                }
                
                let countiesSQL = """
                    SELECT co.name as county, p.name as plan, e.enrollment
                    FROM enrollment_records e
                    JOIN plan_dim p ON p.plan_id = e.plan_id
                    JOIN county_dim co ON co.county_id = e.county_id
                    WHERE e.period_id = \(periodID)
                    ORDER BY e.enrollment DESC
                    LIMIT 50
                """
                let countyRows = try dataStore.database.query(sql: countiesSQL)
                let counties = countyRows.map { row in
                    EnrollmentByCountyByPlan(county: row["county"] as? String ?? "Unknown", plan: row["plan"] as? String ?? "Unknown", enrollment: row["enrollment"] as? Int ?? 0)
                }
                
                await MainActor.run {
                    self.carrierEnrollments = carriers
                    self.countyEnrollments = counties
                    self.isLoading = false
                }
            } catch {
                print("Fetch failed: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}
