import Foundation

/// Pure transport decisions for the dual-deck engine. Task 6 makes manual
/// transport dual-deck-aware: a manual Next can promote an already-prepared
/// standby deck with no smart-gap injection, while every other manual jump
/// (Previous, direct play, seek, stop) must cancel/invalidate the standby and
/// committed-timeline state that was anchored to a "next" the user just left.
///
/// All logic here is side-effect-free so it can be unit-tested without the
/// AVAudioEngine graph. `LocalPlayerSource` calls these to decide *what* to do,
/// then performs the audio-graph work.

/// The outcome of pressing **Next** manually.
public enum ManualNextDecision<ID: Equatable & Sendable>: Equatable, Sendable {
    /// The standby deck is already prepared for exactly this entry — promote it
    /// immediately with NO injected smart-gap. This is the dual-deck-aware fast
    /// path that distinguishes manual Next from the automatic exact-gap transition.
    case promoteStandby(nextID: ID)
    /// No reusable standby (not ready, wrong identity, or no next entry was
    /// prepared) — load the requested entry fresh as the newly active deck.
    case loadFresh(nextID: ID)
    /// There is no next entry to advance to — stop after the current one.
    case stop
}

public enum TransportPolicy {
    /// Decides how a manual Next resolves.
    ///
    /// `nextID` is the real next unplayed entry (or `nil` if none exists).
    /// `willStop` is true when the current entry is a stop-after / performance-stop
    /// boundary — a manual Next still honours that by stopping.
    /// `standbyPhase`/`standbyEntryID` describe the standby deck's current state.
    ///
    /// Promotes the standby only when it is `.ready` or `.scheduled` AND prepared
    /// for exactly the next entry. Otherwise loads fresh. A late/failed/empty
    /// standby never blocks a manual Next — it falls back to a fresh load, which
    /// is the whole point of "no gap, no B-reuse assumption."
    public static func manualNext<ID: Equatable & Sendable>(
        nextID: ID?,
        willStop: Bool,
        standbyPhase: DeckPhase,
        standbyEntryID: ID?
    ) -> ManualNextDecision<ID> {
        guard let nextID, !willStop else { return .stop }
        if (standbyPhase == .ready || standbyPhase == .scheduled),
           let standbyEntryID, standbyEntryID == nextID {
            return .promoteStandby(nextID: nextID)
        }
        return .loadFresh(nextID: nextID)
    }

    /// Whether a manual jump to an arbitrary destination invalidates the prepared
    /// standby. Previous and direct play (jump-to) always do: the standby was
    /// prepared for whatever followed the *old* current entry, which is no longer
    /// the thing about to play.
    public static func jumpClearsStandby() -> Bool { true }

    /// Whether a seek invalidates the committed/uncommitted transition timeline.
    /// Always true: the smart-gap schedule is anchored to specific decoded frame
    /// positions of the active deck, which a seek moves — so the committed plan
    /// (and any in-flight commit) is stale and must be discarded. A seek does NOT
    /// touch the standby deck's prepared file: only the active deck's timeline.
    public static func seekInvalidatesTimeline() -> Bool { true }
}
