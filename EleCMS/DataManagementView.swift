import SwiftUI

struct DataManagementView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    @StateObject private var syncService: SyncService
    
    @State private var loadedPeriods: Set<Int> = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    
    let years = Array((2015...Calendar.current.component(.year, from: Date())).reversed())
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    init(dataStore: DataStore, isMenuOpen: Binding<Bool>) {
        self.dataStore = dataStore
        self._isMenuOpen = isMenuOpen
        self._syncService = StateObject(wrappedValue: SyncService(dataStore: dataStore))
    }
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    VStack(spacing: 24) {
                        yearSelector
                        
                        // Landscape Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ANNUAL LANDSCAPE")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.blue)
                                .kerning(1.2)
                                .padding(.horizontal)
                            
                            ModernCard {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("\(String(format: "%d", selectedYear)) Plan Landscape")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("Benefits, Premiums, & Copays")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    statusIcon(for: selectedYear, month: nil)
                                }
                            }
                            .onTapGesture {
                                handleAction(year: selectedYear, month: nil)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Monthly CPSC Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MONTHLY ENROLLMENT (CPSC)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.blue)
                                .kerning(1.2)
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(1...12, id: \.self) { month in
                                    ModernCard {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(months[month-1])
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                Spacer()
                                                statusIcon(for: selectedYear, month: month)
                                            }
                                            Text("Contract/Plan data")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .onTapGesture {
                                        handleAction(year: selectedYear, month: month)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.bottom, 60)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            if syncService.isSyncing {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ModernCard {
                        VStack(spacing: 16) {
                            ProgressView().tint(.white)
                            Text(syncService.status)
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 220)
                    }
                }
            }
        }
        .onAppear { refreshStatus() }
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
                Text("Data Management")
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
    
    var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(years, id: \.self) { year in
                    Button(action: { selectedYear = year }) {
                        Text(String(format: "%d", year))
                            .font(.system(size: 14, weight: .bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedYear == year ? Color.blue : AppColors.surface)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    func statusIcon(for year: Int, month: Int?) -> some View {
        let isLoaded = isLoaded(year: year, month: month)
        Image(systemName: isLoaded ? "checkmark.circle.fill" : "icloud.and.arrow.down")
            .foregroundColor(isLoaded ? .green : .blue)
            .font(.title3)
    }
    
    func isLoaded(year: Int, month: Int?) -> Bool {
        let key = year * 100 + (month ?? 0)
        return loadedPeriods.contains(key)
    }
    
    func handleAction(year: Int, month: Int?) {
        if isLoaded(year: year, month: month) {
            deleteData(year: year, month: month)
        } else {
            Task {
                await syncService.syncSpecific(year: year, month: month)
                refreshStatus()
            }
        }
    }
    
    func refreshStatus() {
        Task {
            do {
                let periods = try dataStore.database.query(sql: """
                    SELECT year, month FROM periods
                    UNION
                    SELECT DISTINCT year, 0 as month FROM landscape_records
                """)
                let keys = periods.map { row in
                    let y = row["year"] as? Int ?? 0
                    let m = row["month"] as? Int ?? 0
                    return y * 100 + m
                }
                await MainActor.run { self.loadedPeriods = Set(keys) }
            } catch { print("Status failed: \(error)") }
        }
    }
    
    func deleteData(year: Int, month: Int?) {
        Task {
            do {
                if let m = month {
                    let results = try dataStore.database.query(sql: "SELECT period_id FROM periods WHERE year = ? AND month = ?", arguments: [year, m])
                    if let periodID = results.first?["period_id"] as? Int {
                        try dataStore.database.execute(sql: "DELETE FROM enrollment_records WHERE period_id = \(periodID)")
                        try dataStore.database.execute(sql: "DELETE FROM periods WHERE period_id = \(periodID)")
                    }
                } else {
                    try dataStore.database.execute(sql: "DELETE FROM landscape_records WHERE year = \(year)")
                }
                refreshStatus()
            } catch { print("Delete failed: \(error)") }
        }
    }
}
