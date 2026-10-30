import SwiftUI

struct MainWindow: View {
    @State private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(228)
        } detail: {
            DetailView(appState: appState)
                .toolbar { BrowserToolbar(appState: appState) }
        }
        .inspector(isPresented: inspectorBinding) {
            InspectorView(appState: appState)
                .inspectorColumnWidth(min: 240, ideal: 272, max: 320)
        }
        .navigationTitle(appState.windowTitle)
        .navigationSubtitle(appState.windowSubtitle)
        .sheet(isPresented: $appState.showDeleteSheet) {
            DeleteConfirmationSheet(appState: appState)
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                ToastView(text: toast.text)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: appState.toast)
        .frame(minWidth: 900, minHeight: 560)
        .onKeyPress(.escape) {
            appState.clearSelection()
            return .handled
        }
        .focusedSceneValue(\.appState, appState)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { appState.inspectorShown && appState.screen == .browser },
            set: { appState.inspectorShown = $0 }
        )
    }
}

private struct DetailView: View {
    var appState: AppState

    var body: some View {
        switch appState.screen {
        case .browser:
            BrowserView(appState: appState)
        case .storage:
            StorageBackupView(appState: appState)
        case .connect:
            ConnectDeviceView(appState: appState)
        }
    }
}

#Preview {
    MainWindow()
        .frame(width: 1280, height: 800)
}
