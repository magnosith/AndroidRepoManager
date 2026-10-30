import Foundation
import Observation

/// Mirrors the Settings scene's General / Connections / Transfers tabs.
/// Backed by `UserDefaults` directly so it can be shared by `AppState`
/// (a plain `@Observable` class) and the `Settings` scene alike.
@Observable
final class AppSettings {
    /// Shared by the main window and the Settings scene, which are separate
    /// SwiftUI scenes and therefore need the same instance to stay in sync.
    static let shared = AppSettings()

    private let defaults: UserDefaults

    var showHiddenFiles: Bool { didSet { defaults.set(showHiddenFiles, forKey: Keys.showHidden) } }
    var confirmBeforeDeleting: Bool { didSet { defaults.set(confirmBeforeDeleting, forKey: Keys.confirmDelete) } }
    var defaultView: DefaultViewOption { didSet { defaults.set(defaultView.rawValue, forKey: Keys.defaultView) } }

    var allowADBConnections: Bool { didSet { defaults.set(allowADBConnections, forKey: Keys.allowADB) } }
    var adbPath: String { didSet { defaults.set(adbPath, forKey: Keys.adbPath) } }
    var autoReconnectWifi: Bool { didSet { defaults.set(autoReconnectWifi, forKey: Keys.autoWifi) } }
    var autoMountSD: Bool { didSet { defaults.set(autoMountSD, forKey: Keys.autoSD) } }

    var pullDestination: String { didSet { defaults.set(pullDestination, forKey: Keys.pullDestination) } }
    var keepOriginalDates: Bool { didSet { defaults.set(keepOriginalDates, forKey: Keys.keepDates) } }
    var conflictPolicy: ConflictPolicy { didSet { defaults.set(conflictPolicy.rawValue, forKey: Keys.conflictPolicy) } }

    private enum Keys {
        static let showHidden = "settings.showHidden"
        static let confirmDelete = "settings.confirmDelete"
        static let defaultView = "settings.defaultView"
        static let allowADB = "settings.allowADB"
        static let adbPath = "settings.adbPath"
        static let autoWifi = "settings.autoWifi"
        static let autoSD = "settings.autoSD"
        static let pullDestination = "settings.pullDestination"
        static let keepDates = "settings.keepDates"
        static let conflictPolicy = "settings.conflictPolicy"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showHiddenFiles = defaults.object(forKey: Keys.showHidden) as? Bool ?? false
        confirmBeforeDeleting = defaults.object(forKey: Keys.confirmDelete) as? Bool ?? true
        defaultView = DefaultViewOption(rawValue: defaults.string(forKey: Keys.defaultView) ?? "") ?? .list
        allowADBConnections = defaults.object(forKey: Keys.allowADB) as? Bool ?? true
        adbPath = defaults.string(forKey: Keys.adbPath) ?? "/opt/homebrew/bin/adb"
        autoReconnectWifi = defaults.object(forKey: Keys.autoWifi) as? Bool ?? true
        autoMountSD = defaults.object(forKey: Keys.autoSD) as? Bool ?? true
        pullDestination = defaults.string(forKey: Keys.pullDestination) ?? "~/Downloads/Android"
        keepOriginalDates = defaults.object(forKey: Keys.keepDates) as? Bool ?? true
        conflictPolicy = ConflictPolicy(rawValue: defaults.string(forKey: Keys.conflictPolicy) ?? "") ?? .ask
    }
}
