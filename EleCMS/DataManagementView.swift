import SwiftUI

struct DataManagementView: View {
    let dataStore: DataStore
    @StateObject private var syncService: SyncService
    
    @State private var loadedPeriods: Set<Int> = []
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    
    let years = Array((2015...Calendar.current.component(.year, from: Date())).reversed())
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    init(dataStore: DataStore) {
        self.dataStore = dataStore
        _syncService = StateObject(wrappedValue: SyncService(dataStore: dataStore))
    }
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Data Catalog")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("CPSC & Landscape Records")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                // Year Selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(years, id: \.self) { year in
                            Button(action: { selectedYear = year }) {
                                Text(String(format: "%d", year))
                                    .fontWeight(.bold)
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Landscape Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ANNUAL LANDSCAPE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
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
                                print("DEBUG: Landscape card tapped for year \(selectedYear)")
                                handleAction(year: selectedYear, month: nil)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Monthly CPSC Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MONTHLY ENROLLMENT (CPSC)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
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
                                        print("DEBUG: CPSC card tapped for \(selectedYear)-\(month)")
                                        handleAction(year: selectedYear, month: month)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            
            // Progress Overlay
            if syncService.isSyncing {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    ModernCard {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.white)
                            Text(syncService.status)
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 200)
                    }
                }
            }
        }
        .onAppear {
            refreshStatus()
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
        // Month 0 or nil = Landscape for that year
        let key = year * 100 + (month ?? 0)
        return loadedPeriods.contains(key)
    }
    
    func handleAction(year: Int, month: Int?) {
        if isLoaded(year: year, month: month) {
            print("DEBUG: Deleting data for \(year)-\(month ?? 0)")
            deleteData(year: year, month: month)
        } else {
            print("DEBUG: Starting sync for \(year)-\(month ?? 0)")
            Task {
                await syncService.syncSpecific(year: year, month: month)
                print("DEBUG: Sync finished, refreshing status")
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
                await MainActor.run {
                    self.loadedPeriods = Set(keys)
                }
            } catch {
                print("Failed to fetch periods: \(error)")
            }
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
                    // Delete landscape for year
                    try dataStore.database.execute(sql: "DELETE FROM landscape_records WHERE year = \(year)")
                    // Also delete from periods if we ever track landscape there, 
                    // but for now it's tracked by a synthetic period key (year * 100)
                    try dataStore.database.execute(sql: "DELETE FROM periods WHERE year = \(year) AND month = 0")
                }
                refreshStatus()
            } catch {
                print("Delete failed: \(error)")
            }
        }
    }
}
