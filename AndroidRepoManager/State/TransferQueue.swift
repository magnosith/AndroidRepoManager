import Foundation
import Observation

/// Serial transfer queue: one active transfer at a time, the rest wait.
/// For now progress is simulated with a timer; a real backend would report
/// actual bytes copied instead of `tick()` manufacturing them.
@Observable
final class TransferQueue {
    var items: [Transfer] = []

    /// Called on the main actor whenever a transfer finishes, so `AppState`
    /// can apply the result to the fake file tree / mac file list and show a toast.
    var onComplete: ((Transfer) -> Void)?

    private var timer: Timer?
    private let simulatedSpeed: Int64 = 34_000_000 // ~34 MB/s

    var activeCount: Int {
        items.filter { $0.status == .waiting || $0.status == .active }.count
    }

    var summaryText: String {
        let active = items.filter { $0.status == .active || $0.status == .waiting }
        if active.isEmpty {
            return items.isEmpty ? "Idle" : "All transfers complete"
        }
        guard let current = items.first(where: { $0.status == .active }) else {
            return "\(active.count) remaining"
        }
        let percent = Int(current.fractionDone * 100)
        return "\(active.count) remaining · \(percent)%"
    }

    func enqueue(_ transfer: Transfer) {
        items.append(transfer)
        startTimerIfNeeded()
    }

    func clearCompleted() {
        items.removeAll { $0.status == .done || $0.status == .cancelled }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Real transfers (ADB/MTP/SD) are driven by `AppState`'s own runner, which flips
    /// their status directly — this ticker only simulates progress for the sample-data demo.
    @MainActor
    private func tick() {
        if let activeIdx = items.firstIndex(where: { $0.status == .active && !$0.isReal }) {
            var transfer = items[activeIdx]
            transfer.speedBytesPerSecond = simulatedSpeed
            transfer.doneBytes = min(transfer.totalBytes, transfer.doneBytes + Int64(Double(simulatedSpeed) * 0.25))
            if transfer.doneBytes >= transfer.totalBytes {
                transfer.status = .done
                transfer.speedBytesPerSecond = 0
                items[activeIdx] = transfer
                onComplete?(transfer)
            } else {
                items[activeIdx] = transfer
            }
        } else if !items.contains(where: { $0.status == .active }),
                  let waitingIdx = items.firstIndex(where: { $0.status == .waiting && !$0.isReal }) {
            items[waitingIdx].status = .active
        } else if items.allSatisfy({ $0.status == .done || $0.status == .cancelled }) {
            timer?.invalidate()
            timer = nil
        }
    }
}
