import SwiftUI

struct TransfersPopoverView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transfers").font(.system(size: 14, weight: .semibold))
                    Text(appState.transferQueue.summaryText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Completed") {
                    appState.transferQueue.clearCompleted()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.accentColor)
                .disabled(!hasCompleted)
            }
            .padding(14)

            Divider()

            if appState.transferQueue.items.isEmpty {
                VStack(spacing: 6) {
                    Text("No transfers yet.")
                        .foregroundStyle(.secondary)
                    Text("Pull files to copy them to your Mac, or drop files on the browser to copy them to the device.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                }
                .padding(28)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.transferQueue.items) { transfer in
                            TransferRow(appState: appState, transfer: transfer)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 380)
    }

    private var hasCompleted: Bool {
        appState.transferQueue.items.contains { $0.status == .done || $0.status == .cancelled }
    }
}

private struct TransferRow: View {
    var appState: AppState
    var transfer: Transfer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: transfer.direction == .pull ? "arrow.down" : "arrow.up")
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(iconColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.name).font(.system(size: 12.5)).lineLimit(1)
                ProgressView(value: transfer.fractionDone)
                    .tint(progressColor)
                Text(transfer.detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if transfer.status == .waiting || transfer.status == .active {
                Button {
                    appState.cancelTransfer(transfer.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var iconColor: Color {
        switch transfer.direction {
        case .pull: return Color.accentColor
        case .push, .backup: return .green
        }
    }

    private var progressColor: Color {
        switch transfer.status {
        case .done: return .green
        case .cancelled: return .gray
        default: return .accentColor
        }
    }
}
