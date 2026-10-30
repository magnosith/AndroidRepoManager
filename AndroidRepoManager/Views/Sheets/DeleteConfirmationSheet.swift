import SwiftUI

struct DeleteConfirmationSheet: View {
    var appState: AppState

    var body: some View {
        if let pending = appState.pendingDelete {
            VStack(alignment: .leading, spacing: 16) {
                Text(title(pending))
                    .font(.system(size: 17, weight: .semibold))

                Text("This permanently removes the files from the device. Android doesn't keep a Trash for files deleted over USB, ADB or Wi‑Fi, so this can't be undone.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pending.nodes.prefix(4)) { node in
                        HStack {
                            Text(node.name).lineLimit(1)
                            Spacer()
                            Text(Format.size(appState.currentDevice?.size(of: node) ?? node.size))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12.5))
                    }
                    if pending.nodes.count > 4 {
                        Text("and \(pending.nodes.count - 4) more · \(Format.size(appState.selectedBytes))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Spacer()
                    Button("Cancel") { appState.cancelDeleteSheet() }
                        .keyboardShortcut(.cancelAction)
                    Button(role: .destructive) {
                        appState.confirmDelete()
                    } label: {
                        Text(pending.nodes.count == 1 ? "Delete" : "Delete \(pending.nodes.count) Items")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 420)
        }
    }

    private func title(_ pending: PendingDelete) -> String {
        if pending.nodes.count == 1 {
            return "Delete \"\(pending.nodes[0].name)\" from \(pending.deviceName)?"
        }
        return "Delete \(pending.nodes.count) items from \(pending.deviceName)?"
    }
}
