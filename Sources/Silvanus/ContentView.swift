import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            MeetingList(page: model.sidebar ?? .all)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            MeetingDetail()
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

struct MeetingList: View {
    @Environment(AppModel.self) private var model
    let page: SidebarItem

    /// Nothing is starred yet: starring arrives with the meeting type.
    private var visible: [String] {
        page == .starred ? [] : model.meetings
    }

    var body: some View {
        @Bindable var model = model
        List(visible, id: \.self, selection: $model.selection) { title in
            Text(title)
                .tag(title)
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No Meetings",
                    systemImage: page.symbol,
                    description: Text("Meetings you record show up here.")
                )
            }
        }
        .navigationTitle(page.title)
    }
}

struct MeetingDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let title = model.selection {
            Text(title)
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Meeting Selected", systemImage: "sidebar.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
