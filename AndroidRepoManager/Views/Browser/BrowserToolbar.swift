import SwiftUI

struct BrowserToolbar: ToolbarContent {
    @Bindable var appState: AppState

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { appState.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!appState.canGoBack)
            Button { appState.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!appState.canGoForward)
        }

        if appState.screen == .browser {
            ToolbarItemGroup {
                Picker("View", selection: Binding(
                    get: { appState.viewMode },
                    set: { appState.viewMode = $0 }
                )) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 76)
            }

            ToolbarItemGroup {
                Button("New Folder") { appState.createNewFolder() }
                Button {
                    appState.presentPushPicker()
                } label: {
                    Label("Push", systemImage: "arrow.up")
                }
                .help("Copy files from your Mac to the device")
                Button {
                    appState.pullSelectionToMac()
                } label: {
                    Label("Pull to Mac", systemImage: "arrow.down")
                }
                .disabled(appState.selection.isEmpty)
                .help("Copy selected items to your Mac")
                Button(role: .destructive) {
                    appState.requestDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(appState.selection.isEmpty)
                .help("Delete from device (⌘⌫)")
            }
        }

        ToolbarItem {
            Button {
                appState.queuePopoverShown.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                    if appState.transferQueue.activeCount > 0 {
                        Text("\(appState.transferQueue.activeCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 7, y: -7)
                    }
                }
            }
            .help("Transfers")
            .popover(isPresented: Binding(
                get: { appState.queuePopoverShown },
                set: { appState.queuePopoverShown = $0 }
            )) {
                TransfersPopoverView(appState: appState)
            }
        }

        if appState.screen == .browser {
            ToolbarItem {
                TextField("Search", text: $appState.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onKeyPress(.escape) {
                        appState.search = ""
                        return .handled
                    }
            }

            ToolbarItem {
                Button {
                    appState.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .foregroundStyle(appState.inspectorShown ? Color.accentColor : Color.primary)
                .help("Inspector")
            }
        }
    }
}
