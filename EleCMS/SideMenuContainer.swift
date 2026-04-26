import SwiftUI

struct SideMenuContainer<Content: View>: View {
    @Binding var isMenuOpen: Bool
    @Binding var selectedDestination: NavDestination
    let content: Content
    
    init(isMenuOpen: Binding<Bool>, selectedDestination: Binding<NavDestination>, @ViewBuilder content: () -> Content) {
        self._isMenuOpen = isMenuOpen
        self._selectedDestination = selectedDestination
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Side Menu is the bottom layer
            SideMenuView(selectedDestination: $selectedDestination, isMenuOpen: $isMenuOpen)
            
            // Main Content slides on top
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(AppColors.background)
                .cornerRadius(isMenuOpen ? 20 : 0)
                .offset(x: isMenuOpen ? 260 : 0)
                .shadow(color: .black.opacity(isMenuOpen ? 0.5 : 0), radius: 10, x: -5, y: 0)
                .allowsHitTesting(!isMenuOpen)
            
            if isMenuOpen {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 260)
                        .allowsHitTesting(false)
                    
                    Color.black.opacity(0.01)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuOpen = false
                            }
                        }
                }
                .ignoresSafeArea()
            }
        }
        .background(AppColors.background)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isMenuOpen)
    }
}
