import SwiftUI
import Charts

struct CarrierDeepDiveView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    
    @State private var selectedCarrier: String?
    @State private var availableCarriers: [String] = []
    
    @State private var totalEnrollment: Int = 0
    @State private var stateBreakdown: [StateShare] = []
    @State private var typeBreakdown: [TypeShare] = []
    @State private var trendData: [TrendPoint] = []
    @State private var isLoading = false
    
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
    
    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
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
        }
        .onAppear { fetchAvailableCarriers() }
    }
    
    var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { withAnimation(.spring()) { isMenuOpen = true } }) {
                    ZStack {
                        Circle().fill(AppColors.surface).frame(width: 40, height: 40)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Spacer()
                Text("Carrier Deep-dive")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal)
            .frame(height: 64)
            .background(AppColors.background.opacity(0.95))
            
            Divider().background(Color.white.opacity(0.1))
        }
    }
    
    var carrierSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT CARRIER")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.white.opacity(0.4))
                .kerning(1.2)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableCarriers, id: \.self) { carrier in
                        Button(action: {
                            selectedCarrier = carrier
                            fetchCarrierData(carrier: carrier)
                        }) {
                            Text(carrier)
                                .font(.system(size: 14, weight: .bold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(selectedCarrier == carrier ? Color.blue : AppColors.surface)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    func carrierContent(for carrier: String) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // High-level Stats
            VStack(spacing: 16) {
                ModernCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOTAL ENROLLMENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(compactFormat(totalEnrollment))
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            
            // Trend Chart
            if trendData.count > 1 {
                VStack(alignment: .leading, spacing: 16) {
                    Text("GROWTH TREND")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white.opacity(0.4))
                        .kerning(1.2)
                        .padding(.horizontal)
                    
                    ModernCard {
                        Chart {
                            ForEach(trendData) { point in
                                LineMark(x: .value("Month", point.date), y: .value("Enrollment", point.enrollment))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                    .lineStyle(StrokeStyle(lineWidth: 3))
                                AreaMark(x: .value("Month", point.date), y: .value("Enrollment", point.enrollment))
                                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    }
                    .padding(.horizontal)
                }
            }
            
            // Geographic Footprint
            VStack(alignment: .leading, spacing: 16) {
                Text("GEOGRAPHIC FOOTPRINT")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white.opacity(0.4))
                    .kerning(1.2)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    let maxVal = stateBreakdown.map { $0.enrollment }.max() ?? 1
                    ForEach(Array(stateBreakdown.enumerated()), id: \.element.id) { index, share in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("#\(index + 1) \(share.state)").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(compactFormat(share.enrollment)).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                                        Text(String(format: "%.1f%% of book", share.percentage)).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05)).frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * CGFloat(share.enrollment) / CGFloat(maxVal), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Business Mix
            VStack(alignment: .leading, spacing: 16) {
                Text("BUSINESS MIX")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white.opacity(0.4))
                    .kerning(1.2)
                    .padding(.horizontal)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(typeBreakdown) { type in
                        ModernCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(type.type.uppercased()).font(.system(size: 8, weight: .black)).foregroundColor(.blue)
                                Text(compactFormat(type.enrollment)).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
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
    
    var selectCarrierPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            Text("Select a Carrier").font(.headline).foregroundColor(.white)
            Text("Choose a carrier above to analyze their market performance and business mix.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    func compactFormat(_ n: Int) -> String {
        let num = Double(n)
        if num >= 1_000_000 { return String(format: "%.1fM", num / 1_000_000) }
        if num >= 1_000 { return String(format: "%.1fK", num / 1_000) }
        return "\(n)"
    }
    
    func fetchAvailableCarriers() {
        Task {
            do {
                let rows = try dataStore.database.query(sql: "SELECT name FROM carrier_dim ORDER BY name")
                let carriers = rows.compactMap { $0["name"] as? String }
                await MainActor.run { self.availableCarriers = carriers }
            } catch { print("Carriers failed: \(error)") }
        }
    }
    
    func fetchCarrierData(carrier: String) {
        isLoading = true
        Task {
            do {
                // Get latest period
                let pRow = try dataStore.database.query(sql: "SELECT period_id FROM periods ORDER BY year DESC, month DESC LIMIT 1")
                guard let pid = pRow.first?["period_id"] as? Int else { isLoading = false; return }
                
                // 1. Total
                let totalRow = try dataStore.database.query(sql: "SELECT SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id WHERE c.name = '\(carrier)' AND e.period_id = \(pid)")
                let total = totalRow.first?["total"] as? Int ?? 0
                
                // 2. State Breakdown
                let stateRows = try dataStore.database.query(sql: "SELECT co.state, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN county_dim co ON co.county_id = e.county_id WHERE c.name = '\(carrier)' AND e.period_id = \(pid) GROUP BY co.state ORDER BY total DESC")
                let states = stateRows.map { StateShare(state: $0["state"] as? String ?? "??", enrollment: $0["total"] as? Int ?? 0, percentage: Double($0["total"] as? Int ?? 0) / Double(total) * 100) }
                
                // 3. Type Mix
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
                    WHERE c.name = '\(carrier)' AND e.period_id = \(pid)
                    GROUP BY mix_type
                    ORDER BY total DESC
                """)
                let mix = typeRows.map { TypeShare(type: $0["mix_type"] as? String ?? "Other", enrollment: $0["total"] as? Int ?? 0) }
                
                // 4. Trend
                let trendRows = try dataStore.database.query(sql: "SELECT pe.year, pe.month, SUM(e.enrollment) as total FROM enrollment_records e JOIN plan_dim p ON p.plan_id = e.plan_id JOIN carrier_dim c ON c.carrier_id = p.carrier_id JOIN periods pe ON e.period_id = pe.period_id WHERE c.name = '\(carrier)' GROUP BY pe.period_id, pe.year, pe.month ORDER BY pe.year ASC, pe.month ASC")
                let trend = trendRows.map { TrendPoint(year: $0["year"] as? Int ?? 0, month: $0["month"] as? Int ?? 0, enrollment: $0["total"] as? Int ?? 0) }
                
                await MainActor.run {
                    self.totalEnrollment = total
                    self.stateBreakdown = states
                    self.typeBreakdown = mix
                    self.trendData = trend
                    self.isLoading = false
                }
            } catch { print("Carrier data failed: \(error)"); await MainActor.run { self.isLoading = false } }
        }
    }
}
