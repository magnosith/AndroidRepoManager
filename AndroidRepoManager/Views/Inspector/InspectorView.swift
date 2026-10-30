import SwiftUI

struct InspectorView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(14)
            }
            Divider()
            footer
                .padding(14)
        }
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private var content: some View {
        if appState.selectedNodes.count > 1 {
            MultiSelectionInspector(appState: appState)
        } else if let node = appState.selectedNodes.first ?? appState.currentFolder {
            SingleNodeInspector(appState: appState, node: node)
        } else {
            Text("No device selected")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                appState.pullSelectionToMac()
            } label: {
                Text(pullLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.selectedNodes.isEmpty)

            if !appState.selectedNodes.isEmpty {
                Button(role: .destructive) {
                    appState.requestDelete()
                } label: {
                    Text("Delete…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var pullLabel: String {
        let count = appState.selectedNodes.count
        if count <= 1 { return "Pull to Mac" }
        return "Pull \(count) Items to Mac"
    }
}

private struct SingleNodeInspector: View {
    var appState: AppState
    var node: FileNode

    private var device: Device? { appState.currentDevice }
    private var kind: FileKindInfo { FileKind.info(forName: node.name, isFolder: node.isFolder) }
    private var sizeBytes: Int64 { device?.size(of: node) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewArea

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Information")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 0) {
                    InfoRow(key: "Kind", value: node.isFolder ? "Folder" : kind.label)
                    InfoRow(key: "Size", value: Format.size(sizeBytes))
                    InfoRow(key: "Modified", value: Format.date(node.modified))
                    InfoRow(key: "Where", value: whereText)
                    if let device {
                        InfoRow(key: "Device", value: "\(device.name) · \(device.connection.connectionLabel)")
                        InfoRow(key: "Access", value: accessText(device))
                    }
                }
            }
        }
    }

    private var subtitle: String {
        if node.isFolder {
            return "Folder — \(Format.size(sizeBytes)), \(Format.itemCount(node.childIDs.count))"
        }
        return "\(kind.label) — \(Format.size(sizeBytes))"
    }

    private var whereText: String {
        guard let device else { return "" }
        let chain = device.ancestorPath(to: node.id).dropLast()
        let names = chain.enumerated().map { index, n in index == 0 ? device.name : n.name }
        return names.isEmpty ? device.name : names.joined(separator: " › ")
    }

    private func accessText(_ device: Device) -> String {
        device.connection == .sd ? "Read & Write · exFAT" : "Read & Write"
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
            if node.isFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(hex: "4aa8f8"))
            } else if kind.isMedia {
                VStack {
                    Spacer()
                    Text(node.name)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack {
                    Spacer()
                    Text(kind.extensionLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(kind.color, in: RoundedRectangle(cornerRadius: 5))
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(height: 168)
    }
}

private struct InfoRow: View {
    var key: String
    var value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct MultiSelectionInspector: View {
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
                Text("\(appState.selectedNodes.count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 168)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.selectedNodes.count) items")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(Format.size(appState.selectedBytes)) on \(appState.currentDevice?.name ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                ForEach(appState.selectedNodes.prefix(8)) { node in
                    HStack {
                        Text(node.name).lineLimit(1)
                        Spacer()
                        Text(Format.size(appState.currentDevice?.size(of: node) ?? 0))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
                if appState.selectedNodes.count > 8 {
                    Text("and \(appState.selectedNodes.count - 8) more · \(Format.size(appState.selectedBytes))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
