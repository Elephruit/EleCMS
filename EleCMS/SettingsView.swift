import SwiftUI

struct SettingsView: View {
    let dataStore: DataStore
    @Binding var isMenuOpen: Bool
    
    @State private var tableCounts: [String: Int] = [:]
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                PageHeader(title: "Advanced Settings", subtitle: nil, isMenuOpen: $isMenuOpen)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Storage Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("STORAGE & INTEGRITY")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white.opacity(0.4))
                                .kerning(1.2)
                                .padding(.horizontal)
                            
                            ModernCard {
                                VStack(spacing: 16) {
                                    diagnosticRow(title: "Enrollment Records", count: tableCounts["enrollment_records"] ?? 0)
                                    diagnosticRow(title: "Landscape Records", count: tableCounts["landscape_records"] ?? 0)
                                    diagnosticRow(title: "Tracked Plans", count: tableCounts["plan_dim"] ?? 0)
                                    diagnosticRow(title: "Known Carriers", count: tableCounts["carrier_dim"] ?? 0)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Advanced Actions
                        VStack(alignment: .leading, spacing: 16) {
                            Text("DANGER ZONE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.red.opacity(0.6))
                                .kerning(1.2)
                                .padding(.horizontal)
                            
                            Button(action: { showingDeleteConfirmation = true }) {
                                ModernCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Clear All Data")
                                                .font(.headline)
                                                .foregroundColor(.red)
                                            Text("Wipe all enrollment and landscape records.")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        Image(systemName: "trash.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView().tint(.white).scaleEffect(1.5)
                        Text("Purging Database...").foregroundColor(.white).bold()
                    }
                }
            }
        }
        .onAppear { fetchDiagnostics() }
        .alert("Are you absolutely sure?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) { purgeData() }
        } message: {
            Text("This will permanently delete all loaded enrollment and landscape data. This action cannot be undone.")
        }
    }
    
    func diagnosticRow(title: String, count: Int) -> some View {
        HStack {
            Text(title).foregroundColor(.white).font(.system(size: 14))
            Spacer()
            Text(UIFormatter.formatNumber(count))
                .foregroundColor(.blue)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
        }
    }
    
    func fetchDiagnostics() {
        Task {
            do {
                let tables = ["enrollment_records", "landscape_records", "plan_dim", "carrier_dim"]
                var counts: [String: Int] = [:]
                for table in tables {
                    let row = try dataStore.database.query(sql: "SELECT COUNT(*) as c FROM \(table)")
                    counts[table] = row.first?["c"] as? Int ?? 0
                }
                await MainActor.run { self.tableCounts = counts }
            } catch { print("Diagnostics failed: \(error)") }
        }
    }
    
    func purgeData() {
        isDeleting = true
        Task {
            do {
                let tables = ["enrollment_records", "landscape_records", "plan_dim", "carrier_dim", "periods", "county_dim"]
                for table in tables {
                    try dataStore.database.execute(sql: "DELETE FROM \(table)")
                }
                try dataStore.database.execute(sql: "VACUUM")
                fetchDiagnostics()
                await MainActor.run { isDeleting = false }
            } catch {
                print("Purge failed: \(error)")
                await MainActor.run { isDeleting = false }
            }
        }
    }
}
