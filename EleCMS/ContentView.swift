import SwiftUI

struct MainContainerView: View {
    let dataStore: DataStore
    
    @State private var isMenuOpen = false
    @State private var navStack: [NavDestination] = [.marketOverview]
    
    var currentDestination: NavDestination {
        navStack.last ?? .marketOverview
    }
    
    var body: some View {
        SideMenuContainer(isMenuOpen: $isMenuOpen, selectedDestination: Binding(
            get: { self.currentDestination },
            set: { newDest in
                if newDest != self.currentDestination {
                    self.navStack.append(newDest)
                }
            }
        )) {
            Group {
                switch currentDestination {
                case .marketOverview:
                    DashboardView(dataStore: dataStore, isMenuOpen: $isMenuOpen)
                case .geographicDeepDive:
                    GeographicDeepDiveView(dataStore: dataStore, isMenuOpen: $isMenuOpen, selectedDestination: Binding(
                        get: { self.currentDestination },
                        set: { self.navStack.append($0) }
                    ))
                case .carrierDeepDive:
                    CarrierDeepDiveView(dataStore: dataStore, isMenuOpen: $isMenuOpen, selectedDestination: Binding(
                        get: { self.currentDestination },
                        set: { self.navStack.append($0) }
                    ))
                case .planDeepDive(let planID):
                    PlanDetailView(dataStore: dataStore, isMenuOpen: $isMenuOpen, planID: planID, onBack: {
                        if navStack.count > 1 {
                            _ = navStack.removeLast()
                        }
                    })
                case .dataCatalog:
                    DataManagementView(dataStore: dataStore, isMenuOpen: $isMenuOpen)
                case .settings:
                    SettingsView(dataStore: dataStore, isMenuOpen: $isMenuOpen)
                }
            }
            .id(currentDestination)
        }
    }
}

struct ContentView: View {
    @State private var dataStore: DataStore?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let dataStore = dataStore {
                MainContainerView(dataStore: dataStore)
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
                    ProgressView("Booting Intelligence Engine...")
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
            Theme.setup()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
