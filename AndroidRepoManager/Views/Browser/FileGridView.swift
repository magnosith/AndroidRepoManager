import SwiftUI
import AppKit

struct FileGridView: View {
    var appState: AppState

    private let columns = [GridItem(.adaptive(minimum: 112), spacing: 4)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(appState.visibleChildren) { node in
                    GridTile(appState: appState, node: node)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 90)
        }
    }
}

private struct GridTile: View {
    var appState: AppState
    var node: FileNode

    private var isSelected: Bool { appState.selection.contains(node.id) }
    private var kind: FileKindInfo { FileKind.info(forName: node.name, isFolder: node.isFolder) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(node.isFolder ? Color.clear : Color(nsColor: .quaternaryLabelColor).opacity(0.25))
                    .frame(width: 84, height: 84)
                if node.isFolder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "4aa8f8"))
                } else if kind.isMedia {
                    VStack {
                        Spacer()
                        Text(kind.extensionLabel)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 72, height: 72)
                    .background(kind.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack {
                        Spacer()
                        Text(kind.extensionLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(kind.color, in: RoundedRectangle(cornerRadius: 4))
                            .padding(.bottom, 10)
                    }
                    .frame(width: 58, height: 74)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Text(node.name)
                .font(.system(size: 11.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            Text(node.isFolder ? Format.itemCount(node.childIDs.count) : Format.size(node.size))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { appState.openItem(node) }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            appState.handleClick(on: node.id, shift: flags.contains(.shift), command: flags.contains(.command))
        }
        .applyDragOut(appState: appState, node: node)
    }
}
