import SilvanusKit
import SwiftUI

/// The main window: the kit's frame (DesignKit/Window), with the sidebar (Screens/SidebarView)
/// and an empty canvas until the canvas parts arrive.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PaneLayout(sidebarVisible: model.sidebarVisible) {
            // Search, New Meeting, and Filter join the row when their features land.
            SidebarHeaderRow(sidebarVisible: model.sidebarVisible, toggleSidebar: model.toggleSidebar)
        } sidebar: {
            SidebarView(page: model.sidebar ?? .all)
        } header: {
            EmptyView()
        } canvas: {
            Color.clear
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }
}
