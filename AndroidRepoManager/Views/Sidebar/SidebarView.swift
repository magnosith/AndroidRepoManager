import SwiftUI

struct SidebarView: View {
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Devices") {
                    ForEach(appState.devices) { device in
                        DeviceRow(appState: appState, device: device)
                    }
                }
                if appState.currentDevice != nil {
                    Section("Locations") {
                        ForEach(appState.sidebarLocations) { location in
                            LocationRow(appState: appState, location: location)
                        }
                    }
                    Section("Library") {
                        LibraryRow(
                            title: "Storage & Backup",
                            systemImage: "chart.pie.fill",
                            isSelected: appState.screen == .storage,
                            badge: nil,
                            action: appState.openStorageScreen
                        )
                        LibraryRow(
                            title: "Transfers",
                            systemImage: "arrow.up.arrow.down",
                            isSelected: appState.queuePopoverShown,
                            badge: appState.transferQueue.activeCount > 0 ? "\(appState.transferQueue.activeCount)" : nil,
                            action: { appState.queuePopoverShown.toggle() }
                        )
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Button {
                    appState.openConnectScreen()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Connect Device…")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

private struct DeviceRow: View {
    var appState: AppState
    var device: Device

    private var isSelected: Bool { appState.selectedDeviceID == device.id && appState.screen == .browser }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: device.connection.symbolName)
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(device.connection.connectionLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                appState.ejectDevice(device.id)
            } label: {
                Image(systemName: "eject")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Eject")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .onTapGesture { appState.selectDevice(device.id) }
    }
}

private struct LocationRow: View {
    var appState: AppState
    var location: FileNode

    private var isSelected: Bool {
        appState.screen == .browser && appState.currentFolder?.id == location.id
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(location.name)
        }
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .onTapGesture { appState.openFolder(byID: location.id) }
    }
}

private struct LibraryRow: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var badge: String?
    var action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(title)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .onTapGesture(perform: action)
    }
}
