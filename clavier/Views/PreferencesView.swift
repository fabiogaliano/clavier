import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            ClickingTabView()
                .tabItem {
                    Label("Clicking", systemImage: "cursorarrow.click")
                }

            ScrollingTabView()
                .tabItem {
                    Label("Scrolling", systemImage: "arrow.up.arrow.down")
                }

            AppearanceTabView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            GeneralTabView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 500, height: 500)
        .padding()
    }
}

#Preview {
    PreferencesView()
}
