import Foundation

/// Describes what would make the next unplayed entry ineligible for an automatic
/// standby preparation (i.e. the active deck would stop before reaching it).
public enum StandbyPreparationPolicy {
    /// Mirrors `SmartAutoGapTransitionPolicy` but for the broader decision of whether
    /// standby preparation should happen at all — independent of gap timing.
    public static func shouldPrepare(willStop: Bool) -> Bool {
        !willStop
    }
}

/// Identity of a standby (deck B) preparation: which entry it targets, on which deck,
/// at which `DualDeckState` preparation generation, and against which settings revision.
/// Used to validate that an async preparation step is still relevant after every
/// `await` boundary — current/next entry, deck, and generation must all still match.
public struct StandbyPreparationToken<ID: Sendable & Equatable>: Sendable, Equatable {
    public let deck: DeckID
    public let currentID: ID
    public let nextID: ID
    public let generation: UInt64
    public let settingsRevision: UInt64
    public let pluginConfigurationID: UUID?

    public init(
        deck: DeckID,
        currentID: ID,
        nextID: ID,
        generation: UInt64,
        settingsRevision: UInt64,
        pluginConfigurationID: UUID?
    ) {
        self.deck = deck
        self.currentID = currentID
        self.nextID = nextID
        self.generation = generation
        self.settingsRevision = settingsRevision
        self.pluginConfigurationID = pluginConfigurationID
    }

    /// True when an in-flight token still describes the entry/deck/generation
    /// the caller currently cares about. Settings revision is intentionally excluded:
    /// a gap-only settings change must NOT invalidate an in-flight file/plugin open.
    public func matchesIdentity(deck: DeckID, currentID: ID, nextID: ID, generation: UInt64) -> Bool {
        self.deck == deck && self.currentID == currentID && self.nextID == nextID && self.generation == generation
    }
}

/// Decides whether an already-`ready` standby deck can be reused for a newly observed
/// next-entry, or whether it must be cancelled and re-prepared from scratch.
public enum StandbyReusePolicy {
    /// Reuse is valid only when the candidate entry and its plugin configuration are
    /// unchanged. A reorder that leaves the next entry untouched changes nothing; a
    /// reorder, removal, or per-entry plugin-configuration change invalidates the deck.
    public static func canReuse<ID: Equatable>(
        preparedNextID: ID,
        preparedPluginConfigurationID: UUID?,
        observedNextID: ID?,
        observedPluginConfigurationID: UUID?
    ) -> Bool {
        guard let observedNextID, observedNextID == preparedNextID else { return false }
        return observedPluginConfigurationID == preparedPluginConfigurationID
    }
}
