import SwiftUI

struct GeographicDeepDiveView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    
    @State private var selectedState: String?
    @State private var availableStates: [String] = []
    @State private var totalEnrollment: Int = 0
    @State private var carrierMarketShare: [EnrollmentByCarrier] = []
    @State private var countyBreakdown: [EnrollmentByCountyByPlan] = []
    @State private var isLoading = false
    
    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                PageHeader(title: "Geographic Deep-dive", subtitle: selectedState, isMenuOpen: $isMenuOpen)
                
                if availableStates.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView().tint(.white)
                        Text("Loading Geography...").foregroundColor(.gray)
                    }
                    .padding(.top, 100)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            statePicker
                            
                            if let state = selectedState {
                                analyticsContent(for: state)
                            } else {
                                selectStatePrompt
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
        }
        .onAppear { fetchAvailableStates() }
    }
    
    var statePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(availableStates, id: \.self) { state in
                    Button(action: {
                        selectedState = state
                        fetchStateData(state: state)
                    }) {
                        Text(state)
                            .font(.system(size: 14, weight: .bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedState == state ? Color.blue : AppColors.surface)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    func analyticsContent(for state: String) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Summary Card
            EnrollmentMetricCard(title: "Total Enrollment in \(state)", enrollment: totalEnrollment)
                .padding(.horizontal)
            
            // Market Share
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "Carrier Market Share (\(state))")
                
                VStack(spacing: 12) {
                    let maxVal = carrierMarketShare.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(carrierMarketShare.enumerated()), id: \.element.id) { index, item in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("#\(index + 1) \(item.carrier)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(UIFormatter.compactFormat(item.enrollment))
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)).frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * CGFloat(item.enrollment) / CGFloat(maxVal), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // County Breakdown
            VStack(alignment: .leading, spacing: 16) {
                CustomSectionHeader(title: "County Breakdown")
                
                VStack(spacing: 1) {
                    ForEach(countyBreakdown) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.plan).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                                Text(item.county.uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                            }
                            Spacer()
                            Text(UIFormatter.compactFormat(item.enrollment)).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
                        }
                        .padding()
                        .background(AppColors.surface.opacity(0.4))
                    }
                }
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
                .padding(.horizontal)
            }
        }
    }
    
    var selectStatePrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Select a State").font(.headline).foregroundColor(.white)
            Text("Tap a state at the top to see geographic deep-dive analytics.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    func fetchAvailableStates() {
        Task {
            do {
                let rows = try dataStore.database.query(sql: "SELECT DISTINCT state FROM county_dim WHERE state != '' ORDER BY state")
                let states = rows.compactMap { $0["state"] as? String }
                await MainActor.run { self.availableStates = states }
            } catch { print("States failed: \(error)") }
        }
    }
    
    func fetchStateData(state: String) {
        isLoading = true
        Task {
            do {
                // Get latest period
                let pRow = try dataStore.database.query(sql: "SELECT period_id FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let pid = pRow.first?["period_id"] as? Int else { isLoading = false; return }
                
                let totalRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN county_dim co ON co.county_id = e.county_id WHERE co.state = ? AND e.period_id = ?", arguments: [state, pid])
                let total = totalRow.first?["total"] as? Int ?? 0
                
                let carrierRows = try dataStore.database.query(sql: "SELECT c.name as carrier, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id WHERE co.state = ? AND e.period_id = ? GROUP BY c.carrier_id ORDER BY total DESC LIMIT 15", arguments: [state, pid])
                let carriers = carrierRows.map { EnrollmentByCarrier(carrier: $0["carrier"] as? String ?? "Unknown", enrollment: $0["total"] as? Int ?? 0) }
                
                let countyRows = try dataStore.database.query(sql: "SELECT co.name as county, p.name as plan, e.enrollment FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN county_dim co ON co.county_id = e.county_id WHERE co.state = ? AND e.period_id = ? ORDER BY e.enrollment DESC LIMIT 50", arguments: [state, pid])
                let counties = countyRows.map { EnrollmentByCountyByPlan(county: $0["county"] as? String ?? "Unknown", plan: $0["plan"] as? String ?? "Unknown", enrollment: $0["enrollment"] as? Int ?? 0) }
                
                await MainActor.run {
                    self.totalEnrollment = total
                    self.carrierMarketShare = carriers
                    self.countyBreakdown = counties
                    self.isLoading = false
                }
            } catch { print("State data failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
}
