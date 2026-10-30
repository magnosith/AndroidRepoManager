import SwiftUI

struct StatusBarView: View {
    var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            breadcrumbs
            Spacer(minLength: 8)
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 16)
        .frame(height: 30)
        .overlay(alignment: .top) { Divider() }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(appState.breadcrumbs.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Text("›").foregroundStyle(.tertiary)
                }
                Button {
                    appState.openFolder(byID: node.id)
                } label: {
                    Text(index == 0 ? (appState.currentDevice?.name ?? node.name) : node.name)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == appState.breadcrumbs.count - 1 ? Color.primary : Color.secondary)
            }
        }
        .lineLimit(1)
    }

    private var statusText: String {
        let free = Format.size(appState.currentDevice?.freeBytes ?? 0) + " available"
        let total = appState.visibleChildren.count
        if appState.selection.isEmpty {
            return "\(Format.itemCount(total)), \(free)"
        }
        return "\(appState.selection.count) of \(total) selected, \(free)"
    }
}
