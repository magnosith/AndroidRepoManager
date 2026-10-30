import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    if appState.isLoadingCurrentFolder {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if appState.visibleChildren.isEmpty {
                        EmptyFolderView(appState: appState)
                    } else if appState.viewMode == .list {
                        FileListView(appState: appState)
                    } else {
                        FileGridView(appState: appState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !appState.selection.isEmpty, appState.viewMode == .grid {
                    VStack {
                        Spacer()
                        FloatingSelectionBar(appState: appState)
                            .padding(.bottom, 46)
                    }
                }

                if appState.dragOver {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(Color.accentColor.opacity(0.08))
                        .overlay {
                            Text("Drop to copy to \"\(appState.currentFolder?.name ?? "")\" on \(appState.currentDevice?.name ?? "")")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { appState.clearSelection() }
            .dropDestination(for: URL.self) { urls, _ in
                guard let folder = appState.currentFolder else { return false }
                for url in urls { appState.pushFile(from: url, into: folder.id) }
                return true
            } isTargeted: { appState.dragOver = $0 }

            StatusBarView(appState: appState)
        }
        .task(id: appState.currentFolder?.id) {
            if let folder = appState.currentFolder { appState.ensureLoaded(folder: folder) }
        }
    }
}

private struct EmptyFolderView: View {
    var appState: AppState

    private var isSearching: Bool { !appState.search.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            Text(isSearching ? "No results" : "This folder is empty")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(isSearching
                 ? "No files or folders match \"\(appState.search)\"."
                 : "Pull files to copy them to your Mac, or drop files on the browser to copy them to the device.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FloatingSelectionBar: View {
    var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Text(summaryText)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 12)
                .padding(.trailing, 6)
            Button {
                appState.pullSelectionToMac()
            } label: {
                Text("↓ Pull to Mac")
            }
            .buttonStyle(.borderedProminent)
            Button(role: .destructive) {
                appState.requestDelete()
            } label: {
                Text("Delete")
            }
            .buttonStyle(.bordered)
            Button {
                appState.clearSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }

    private var summaryText: String {
        "\(appState.selection.count) selected · \(Format.size(appState.selectedBytes))"
    }
}
