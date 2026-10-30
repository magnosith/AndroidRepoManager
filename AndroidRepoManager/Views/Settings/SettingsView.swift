import SwiftUI
import AppKit

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ConnectionsSettingsTab()
                .tabItem { Label("Connections", systemImage: "cable.connector") }
            TransfersSettingsTab()
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }
        }
        .frame(width: 460)
        .scenePadding()
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show hidden files", isOn: $settings.showHiddenFiles)
                Text("Items that start with a period, like .thumbnails and .nomedia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Confirm before deleting", isOn: $settings.confirmBeforeDeleting)
                Text("Deleted files can't be recovered from the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Default view", selection: $settings.defaultView) {
                    ForEach(DefaultViewOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConnectionsSettingsTab: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Allow ADB connections", isOn: $settings.allowADBConnections)
                HStack {
                    Text("ADB location")
                    Spacer()
                    Text(settings.adbPath).foregroundStyle(.secondary)
                    Button("Change…") { chooseADBPath() }
                }
            }
            Section {
                Toggle("Reconnect Wi‑Fi devices automatically", isOn: $settings.autoReconnectWifi)
                Toggle("Mount SD cards automatically", isOn: $settings.autoMountSD)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseADBPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.adbPath = url.path
        }
    }
}

private struct TransfersSettingsTab: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Save pulled files to")
                    Spacer()
                    Text(settings.pullDestination).foregroundStyle(.secondary)
                    Button("Choose…") { choosePullDestination() }
                }
                Toggle("Keep original modification dates", isOn: $settings.keepOriginalDates)
            }
            Section {
                Picker("If a file already exists", selection: $settings.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func choosePullDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.pullDestination = url.path
        }
    }
}
