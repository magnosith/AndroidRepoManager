import SwiftUI

struct ConnectDeviceView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Connect an Android Device")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Choose how your device connects. Once it's connected you can read, write and delete its files.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 6)
                .frame(maxWidth: 520)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(ConnectionKind.allCases) { method in
                        MethodCard(method: method, isSelected: appState.connectMethod == method) {
                            appState.connectMethod = method
                        }
                    }
                }

                InstructionsCard(appState: appState)

                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if appState.connecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the device… Unlock your phone to allow access.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if appState.currentDevice != nil {
                    Button("Cancel") { appState.screen = .browser }
                }
                Spacer()
                Button {
                    appState.beginConnecting()
                } label: {
                    if appState.connecting {
                        Text("Connecting…")
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.connecting || !connectReady)
            }
        }
        .font(.system(size: 12.5))
    }

    private var connectReady: Bool {
        guard appState.connectMethod == .wifi else { return true }
        return !appState.wifiAddress.isEmpty && appState.wifiCode.count == 6
    }
}

private struct MethodCard: View {
    var method: ConnectionKind
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: method.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(height: 38)
                VStack(spacing: 2) {
                    Text(method.cardTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(method.cardSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InstructionsCard: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.connectMethod.instructionsTitle)
                .font(.system(size: 14, weight: .semibold))

            ForEach(Array(appState.connectMethod.onboardingSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                        .foregroundStyle(Color.accentColor)
                    Text(step)
                        .font(.system(size: 12.5))
                }
            }

            if appState.connectMethod == .wifi {
                HStack(spacing: 10) {
                    TextField("192.168.1.24:37099", text: $appState.wifiAddress)
                        .textFieldStyle(.roundedBorder)
                    TextField("Pairing code", text: $appState.wifiCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}
