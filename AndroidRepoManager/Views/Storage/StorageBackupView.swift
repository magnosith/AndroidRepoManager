import SwiftUI

struct StorageBackupView: View {
    @Bindable var appState: AppState

    var body: some View {
        if let device = appState.currentDevice {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryCard(device: device)
                    HStack(alignment: .top, spacing: 16) {
                        LargestFoldersCard(appState: appState, device: device)
                        BackupCard(appState: appState, device: device)
                    }
                }
                .padding(24)
            }
        } else {
            Text("No device selected").foregroundStyle(.secondary)
        }
    }
}

private struct SummaryCard: View {
    var device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(Format.size(device.usedBytes))
                        .font(.system(size: 26, weight: .semibold))
                    Text("of \(Format.size(device.capacity)) used")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Format.size(device.freeBytes)) available")
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(device.categories) { category in
                        let fraction = device.usedBytes > 0 ? Double(category.bytes) / Double(device.usedBytes) : 0
                        Color(hex: category.colorHex)
                            .frame(width: max(0, proxy.size.width * fraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .background(Color(nsColor: .separatorColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
            }
            .frame(height: 14)

            HStack(spacing: 20) {
                ForEach(device.categories) { category in
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: category.colorHex)).frame(width: 8, height: 8)
                        Text(category.name)
                        Text(Format.size(category.bytes)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LargestFoldersCard: View {
    var appState: AppState
    var device: Device

    private var maxBytes: Int64 { device.largestFolders.map(\.bytes).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Largest folders")
                .font(.system(size: 14, weight: .semibold))
                .padding(.bottom, 4)
            ForEach(device.largestFolders) { folder in
                Button {
                    if let node = device.children(of: device.root, showHidden: true).first(where: { $0.name == folder.name }) {
                        appState.openFolder(byID: node.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(folder.name)
                            .frame(width: 100, alignment: .leading)
                            .foregroundStyle(Color.primary)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width * (Double(folder.bytes) / Double(maxBytes)))
                        }
                        .frame(height: 6)
                        Text(Format.size(folder.bytes))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BackupCard: View {
    @Bindable var appState: AppState
    var device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Back Up to Mac").font(.system(size: 14, weight: .semibold))
                Text("Copies the selected content to ~/Backups/Android/\(device.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                BackupOptionRow(label: "Photos & Videos", bytes: category("Photos & Videos"), isOn: $appState.backupIncludePhotos)
                Divider()
                BackupOptionRow(label: "Documents", bytes: category("Documents"), isOn: $appState.backupIncludeDocuments)
                Divider()
                BackupOptionRow(label: "Downloads", bytes: downloadFolderBytes, isOn: $appState.backupIncludeDownloads)
                Divider()
                BackupOptionRow(label: "Music & Audio", bytes: category("Audio"), isOn: $appState.backupIncludeAudio)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))

            if appState.backupBusy {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: appState.backupProgress)
                    if let transfer = appState.activeBackupTransfer {
                        Text(transfer.detailText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("Last backup: \(device.lastBackup)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.backupNow()
                } label: {
                    Text(appState.backupBusy ? "Backing Up…" : "Back Up Now (\(Format.size(backupTotal)))")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.backupBusy || backupTotal == 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    private func category(_ name: String) -> Int64 {
        device.categories.first { $0.name == name }?.bytes ?? 0
    }

    private var downloadFolderBytes: Int64 {
        device.largestFolders.first { $0.name.hasPrefix("Download") }?.bytes ?? 0
    }

    private var backupTotal: Int64 {
        var total: Int64 = 0
        if appState.backupIncludePhotos { total += category("Photos & Videos") }
        if appState.backupIncludeDocuments { total += category("Documents") }
        if appState.backupIncludeDownloads { total += downloadFolderBytes }
        if appState.backupIncludeAudio { total += category("Audio") }
        return total
    }
}

private struct BackupOptionRow: View {
    var label: String
    var bytes: Int64
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(Format.size(bytes)).foregroundStyle(.secondary).font(.system(size: 12))
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
