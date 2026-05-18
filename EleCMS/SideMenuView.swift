import SwiftUI

struct SideMenuView: View {
    @Binding var selectedDestination: NavDestination
    @Binding var isMenuOpen: Bool
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Profile/Header Section
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "e.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EleCMS")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Healthcare Intelligence")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // Navigation Links
                VStack(spacing: 8) {
                    menuItem(title: "Market Overview", icon: "chart.pie", destination: .marketOverview)
                    menuItem(title: "Geographic Deep-dive", icon: "map", destination: .geographicDeepDive)
                    menuItem(title: "Carrier Deep-dive", icon: "building.2", destination: .carrierDeepDive)
                    menuItem(title: "Plan Deep-dive", icon: "doc.text.magnifyingglass", destination: .planDeepDive())
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 16)
                    
                    menuItem(title: "Data Management", icon: "server.rack", destination: .dataCatalog)
                    menuItem(title: "Advanced Settings", icon: "gearshape.fill", destination: .settings)
                }
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Powered by CMS CPSC & Landscape")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Version 3.1.0")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(24)
            }
        }
    }
    
    func menuItem(title: String, icon: String, destination: NavDestination) -> some View {
        let isSelected: Bool
        switch (selectedDestination, destination) {
        case (.marketOverview, .marketOverview),
             (.geographicDeepDive, .geographicDeepDive),
             (.carrierDeepDive, .carrierDeepDive),
             (.planDeepDive, .planDeepDive),
             (.dataCatalog, .dataCatalog),
             (.settings, .settings):
            isSelected = true
        default:
            isSelected = false
        }
        
        return Button(action: {
            withAnimation(.spring()) {
                isMenuOpen = false
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                selectedDestination = destination
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .gray)
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(12)
        }
    }
}
