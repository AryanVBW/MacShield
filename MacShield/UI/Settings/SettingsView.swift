import SwiftUI

/// Root settings view with tabbed navigation.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppsSettingsView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }

            BlurSettingsView()
                .tabItem {
                    Label("Chat Blur", systemImage: "eye.slash")
                }

            SecuritySettingsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }

            WatchSettingsView()
                .tabItem {
                    Label("Watch", systemImage: "applewatch")
                }
        }
        .frame(width: 560, height: 480)
    }
}
