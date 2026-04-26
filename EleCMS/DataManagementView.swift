import SwiftUI

struct DataManagementView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    @StateObject private var syncService: SyncService
    
    @State private var loadedPeriods: Set<Int> = []
    
    private let years = Array((2015...Calendar.current.component(.year, from: Date())).reversed())
    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    
    private let currentYear = Calendar.current.component(.year, from: Date())
    private let currentMonth = Calendar.current.component(.month, from: Date())
    
    init(dataStore: DataStore, isMenuOpen: Binding<Bool>) {
        self.dataStore = dataStore
        self._isMenuOpen = isMenuOpen
        self._syncService = StateObject(wrappedValue: SyncService(dataStore: dataStore))
    }
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                PageHeader(title: "Data Management", subtitle: "CMS Records Catalog", isMenuOpen: $isMenuOpen)
                
                ScrollView {
                    LazyVStack(spacing: 40, pinnedViews: [.sectionHeaders]) {
                        ForEach(years, id: \.self) { year in
                            yearSection(year: year)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.bottom, 60)
                }
            }
            
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
                        .frame(width: 240)
                    }
                }
            }
        }
        .onAppear { refreshStatus() }
    }
    
    func yearSection(year: Int) -> some View {
        Section {
            VStack(spacing: 24) {
                // Annual Landscape
                VStack(alignment: .leading, spacing: 12) {
                    Text("ANNUAL LANDSCAPE")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.blue.opacity(0.7))
                        .kerning(1.2)
                        .padding(.horizontal)
                    
                    ModernCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(String(year)) Plan Landscape")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Benefits, Premiums, & Copays")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            statusIcon(for: year, month: nil)
                        }
                    }
                    .onTapGesture { handleAction(year: year, month: nil) }
                    .padding(.horizontal)
                }
                
                // Monthly Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("MONTHLY ENROLLMENT (CPSC)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.blue.opacity(0.7))
                        .kerning(1.2)
                        .padding(.horizontal)
                    
                    let columns = [
                        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
                        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                    ]
                    
                    LazyVGrid(columns: UIDevice.current.userInterfaceIdiom == .pad ? columns : [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(1...12, id: \.self) { month in
                            let isFuture = year == currentYear && month > currentMonth
                            
                            ModernCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(months[month-1])
                                            .font(.headline)
                                            .foregroundColor(isFuture ? .gray : .white)
                                        Spacer()
                                        if !isFuture {
                                            statusIcon(for: year, month: month)
                                        }
                                    }
                                    Text("Contract/Plan data")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                            }
                            .opacity(isFuture ? 0.4 : 1.0)
                            .onTapGesture {
                                if !isFuture { handleAction(year: year, month: month) }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        } header: {
            yearHeader(year: year)
        }
    }
    
    func yearHeader(year: Int) -> some View {
        HStack {
            Text(String(year))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                Task {
                    await syncService.syncEntireYear(year: year)
                    refreshStatus()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Load Entire Year")
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(syncService.isSyncing)
        }
        .padding(.horizontal)
        .padding(.vertical, 16)
        .background(AppColors.background.opacity(0.9))
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
