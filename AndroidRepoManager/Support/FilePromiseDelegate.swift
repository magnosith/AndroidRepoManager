import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Backs dragging a file *out* of the browser onto Finder (or any other app).
/// The OS only calls the load handler once the user actually drops it somewhere,
/// so the real pull from the device is deferred until then.
enum FileDragOut {
    static func makeItemProvider(appState: AppState, device: Device, node: FileNode) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = node.name
        let ext = (node.name as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .data

        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            guard let discovered = device.discovered, let backend = appState.backend(for: device), let remotePath = node.remotePath else {
                completion(nil, false, ShellError.nonZeroExit(1, "This item can't be dragged out."))
                return nil
            }
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let tempURL = tempDir.appendingPathComponent(node.name)
            Task {
                do {
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    try await backend.pull(discovered, remotePath: remotePath, to: tempURL, progress: TransferProgress())
                    completion(tempURL, true, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }
}

extension View {
    /// Lets this view be dragged out to Finder as a real file, pulled from the
    /// device on drop. Only available for real (non-demo) devices, files only
    /// (MTP has no recursive folder download).
    @ViewBuilder
    func applyDragOut(appState: AppState, node: FileNode) -> some View {
        if let device = appState.currentDevice, device.isRemoteBacked, !node.isFolder, node.remotePath != nil {
            self.onDrag { FileDragOut.makeItemProvider(appState: appState, device: device, node: node) }
        } else {
            self
        }
    }
}
