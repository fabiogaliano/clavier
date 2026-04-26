import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            ClickingTabView()
                .tabItem {
                    Label("Hints", systemImage: "cursorarrow.click")
                }

            ScrollingTabView()
                .tabItem {
                    Label("Scrolling", systemImage: "arrow.up.and.down.text.horizontal")
                }

            AppearanceTabView()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }

            GeneralTabView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 540, height: 620)
        .scenePadding(.horizontal)
    }
}

#Preview {
    PreferencesView()
}
