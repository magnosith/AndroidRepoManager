import SwiftUI

/// Flattened row used to feed `Table`'s sort comparators (folder sizes/kinds are
/// computed, not stored directly on `FileNode`).
///
/// `Equatable` matters here, not just for correctness: without it, `Table` can't tell
/// a freshly-recomputed row (same content, new struct instance — happens on every
/// selection change, since `rows` is a plain computed property) from an actually
/// changed one, so it was repainting every row's background from scratch on every
/// click — visible as the selection highlight "finishing" a moment after the click.
private struct BrowserRow: Identifiable, Equatable {
    var id: UUID { node.id }
    var node: FileNode
    var sizeBytes: Int64
    var kindLabel: String
}

struct FileListView: View {
    var appState: AppState

    @State private var sortOrder: [KeyPathComparator<BrowserRow>] = [KeyPathComparator(\.node.name)]

    private var rows: [BrowserRow] {
        guard let device = appState.currentDevice else { return [] }
        return appState.visibleChildren.map { node in
            let kind = FileKind.info(forName: node.name, isFolder: node.isFolder)
            return BrowserRow(node: node, sizeBytes: device.size(of: node), kindLabel: kind.label)
        }
    }

    var body: some View {
        Table(rows, selection: selectionBinding, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.node.name) { row in
                NameCell(node: row.node)
                    .onTapGesture(count: 2) { appState.openItem(row.node) }
                    .applyDragOut(appState: appState, node: row.node)
            }
            TableColumn("Date Modified", value: \.node.modified) { row in
                Text(Format.date(row.node.modified))
                    .foregroundStyle(.secondary)
            }
            .width(168)
            TableColumn("Size", value: \.sizeBytes) { row in
                Text(row.node.isFolder ? Format.itemCount(row.node.childIDs.count) : Format.size(row.node.size))
                    .foregroundStyle(.secondary)
            }
            .width(84)
            TableColumn("Kind", value: \.kindLabel) { row in
                Text(row.kindLabel)
                    .foregroundStyle(.secondary)
            }
            .width(128)
        }
        .onChange(of: sortOrder) { _, newOrder in
            guard let first = newOrder.first else { return }
            switch first.keyPath {
            case \BrowserRow.node.name: appState.setSort(.name)
            case \BrowserRow.node.modified: appState.setSort(.date)
            case \BrowserRow.sizeBytes: appState.setSort(.size)
            case \BrowserRow.kindLabel: appState.setSort(.kind)
            default: break
            }
        }
    }

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(get: { appState.selection }, set: { appState.selection = $0 })
    }
}

private struct NameCell: View {
    var node: FileNode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isFolder ? "folder.fill" : FileKind.symbolName(forName: node.name, isFolder: false))
                .foregroundStyle(node.isFolder ? Color(hex: "4aa8f8") : FileKind.info(forName: node.name, isFolder: false).color)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
    }
}
