import Foundation

@MainActor
public struct BackupChangeTracker {
    public static let pendingKey = "ganfanLibraryNeedsBackup"
    public static let generationKey = "ganfanLibraryChangeGeneration"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasPendingChanges: Bool {
        defaults.bool(forKey: Self.pendingKey)
    }

    public var generation: Int {
        defaults.integer(forKey: Self.generationKey)
    }

    @discardableResult
    public func markChanged() -> Int {
        let nextGeneration = generation &+ 1
        defaults.set(nextGeneration, forKey: Self.generationKey)
        defaults.set(true, forKey: Self.pendingKey)
        return nextGeneration
    }

    /// Clears the library-level flag only if no later change occurred during backup.
    @discardableResult
    public func markBackedUp(ifGenerationMatches expectedGeneration: Int) -> Bool {
        guard generation == expectedGeneration else { return false }
        defaults.set(false, forKey: Self.pendingKey)
        return true
    }
}
