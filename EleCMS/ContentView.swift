import SwiftUI

struct MainTabView: View {
    let dataStore: DataStore
    
    var body: some View {
        TabView {
            DashboardView(dataStore: dataStore)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
            
            DataManagementView(dataStore: dataStore)
                .tabItem {
                    Label("Data", systemImage: "server.rack")
                }
        }
        .accentColor(.blue)
        .onAppear {
            Theme.setup()
        }
    }
}

struct ContentView: View {
    @State private var dataStore: DataStore?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let dataStore = dataStore {
                MainTabView(dataStore: dataStore)
            } else if let error = errorMessage {
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Launch Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    ProgressView("Booting EleCMS...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            initialize()
        }
    }
    
    private func initialize() {
        let fm = FileManager.default
        guard let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            errorMessage = "No access to storage."
            return
        }
        
        do {
            dataStore = try DataStore(directory: documentsURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
