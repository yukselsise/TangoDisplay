import AVFoundation

public enum DeckID: String, CaseIterable, Sendable {
    case a
    case b

    public var other: DeckID { self == .a ? .b : .a }
}

public enum DualDeckGeneration: Sendable {
    public static func next(after generation: UInt64) -> UInt64? {
        generation == .max ? nil : generation + 1
    }
}

public enum DeckPhase: Sendable, Equatable {
    case empty
    case preparing
    case ready
    case scheduled
    case active
    case recycling
    case failed
}

public struct DeckSnapshot<ID: Sendable & Equatable>: Sendable, Equatable {
    public var phase: DeckPhase
    public var entryID: ID?
    public var generation: UInt64

    public init(phase: DeckPhase = .empty, entryID: ID? = nil, generation: UInt64 = 0) {
        self.phase = phase
        self.entryID = entryID
        self.generation = generation
    }
}

public struct DeckPreparationToken<ID: Sendable & Equatable>: Sendable, Equatable {
    public let deck: DeckID
    public let entryID: ID
    public let generation: UInt64

    init(deck: DeckID, entryID: ID, generation: UInt64) {
        self.deck = deck
        self.entryID = entryID
        self.generation = generation
    }
}

public struct DualDeckTransition<ID: Sendable & Equatable>: Sendable, Equatable {
    public let outgoingDeck: DeckID
    public let incomingDeck: DeckID
    public let currentID: ID
    public let nextID: ID
    public let generation: UInt64
    public let outgoingGeneration: UInt64
    public let incomingGeneration: UInt64
    public let settingsRevision: UInt64

    public init(
        outgoingDeck: DeckID,
        incomingDeck: DeckID,
        currentID: ID,
        nextID: ID,
        generation: UInt64,
        outgoingGeneration: UInt64,
        incomingGeneration: UInt64,
        settingsRevision: UInt64
    ) {
        self.outgoingDeck = outgoingDeck
        self.incomingDeck = incomingDeck
        self.currentID = currentID
        self.nextID = nextID
        self.generation = generation
        self.outgoingGeneration = outgoingGeneration
        self.incomingGeneration = incomingGeneration
        self.settingsRevision = settingsRevision
    }
}

public struct DualDeckState<ID: Sendable & Equatable>: Sendable {
    private var decks: [DeckSnapshot<ID>]
    public private(set) var activeDeck: DeckID?
    public private(set) var committedTransition: DualDeckTransition<ID>?
    private var nextTransitionGeneration: UInt64 = 1
    private var nextPreparationGeneration: UInt64 = 1

    public init() {
        decks = [DeckSnapshot(), DeckSnapshot()]
    }

    public subscript(deck: DeckID) -> DeckSnapshot<ID> {
        decks[index(of: deck)]
    }

    public mutating func activate(deck: DeckID, entryID: ID, generation: UInt64) {
        reset(deck: deck.other)
        decks[index(of: deck)] = DeckSnapshot(phase: .active, entryID: entryID, generation: generation)
        activeDeck = deck
        committedTransition = nil
    }

    @discardableResult
    public mutating func beginPreparation(
        deck: DeckID,
        entryID: ID,
        automaticTransitionAllowed: Bool = true
    ) -> DeckPreparationToken<ID>? {
        guard automaticTransitionAllowed, deck != activeDeck else { return nil }
        let generation = nextPreparationGeneration
        nextPreparationGeneration = checkedNext(after: generation)
        decks[index(of: deck)] = DeckSnapshot(phase: .preparing, entryID: entryID, generation: generation)
        committedTransition = nil
        return DeckPreparationToken(deck: deck, entryID: entryID, generation: generation)
    }

    @discardableResult
    public mutating func markReady(_ token: DeckPreparationToken<ID>) -> Bool {
        guard matches(deck: token.deck, entryID: token.entryID, generation: token.generation, phase: .preparing) else { return false }
        decks[index(of: token.deck)].phase = .ready
        return true
    }

    public mutating func commitTransition(
        currentID: ID,
        nextID: ID,
        settingsRevision: UInt64
    ) -> DualDeckTransition<ID>? {
        guard let outgoing = activeDeck else { return nil }
        let incoming = outgoing.other
        let current = self[outgoing]
        let next = self[incoming]
        guard current.phase == .active,
              current.entryID == currentID,
              next.phase == .ready,
              next.entryID == nextID else { return nil }
        let transitionGeneration = nextTransitionGeneration
        nextTransitionGeneration = checkedNext(after: transitionGeneration)
        let token = DualDeckTransition(
            outgoingDeck: outgoing,
            incomingDeck: incoming,
            currentID: currentID,
            nextID: nextID,
            generation: transitionGeneration,
            outgoingGeneration: current.generation,
            incomingGeneration: next.generation,
            settingsRevision: settingsRevision
        )
        decks[index(of: incoming)].phase = .scheduled
        committedTransition = token
        return token
    }

    public mutating func promote(_ token: DualDeckTransition<ID>, settingsRevision: UInt64) -> DeckID? {
        guard committedTransition == token else { return nil }
        guard token.settingsRevision == settingsRevision else {
            decks[index(of: token.incomingDeck)].phase = .ready
            committedTransition = nil
            return nil
        }
        guard
              activeDeck == token.outgoingDeck,
              matches(deck: token.outgoingDeck, entryID: token.currentID, generation: token.outgoingGeneration, phase: .active),
              matches(deck: token.incomingDeck, entryID: token.nextID, generation: token.incomingGeneration, phase: .scheduled)
        else { return nil }
        decks[index(of: token.outgoingDeck)].phase = .recycling
        decks[index(of: token.incomingDeck)].phase = .active
        activeDeck = token.incomingDeck
        committedTransition = nil
        return token.incomingDeck
    }

    @discardableResult
    public mutating func markFailed(_ token: DeckPreparationToken<ID>) -> Bool {
        guard matches(deck: token.deck, entryID: token.entryID, generation: token.generation, phase: .preparing) else { return false }
        decks[index(of: token.deck)].phase = .failed
        return true
    }

    @discardableResult
    public mutating func recycle(_ token: DeckPreparationToken<ID>) -> Bool {
        guard matches(deck: token.deck, entryID: token.entryID, generation: token.generation), token.deck != activeDeck else { return false }
        decks[index(of: token.deck)].phase = .recycling
        committedTransition = nil
        return true
    }

    public mutating func reset(deck: DeckID) {
        let invalidatedGeneration = checkedNext(after: self[deck].generation)
        decks[index(of: deck)] = DeckSnapshot(generation: invalidatedGeneration)
        if activeDeck == deck { activeDeck = nil }
        committedTransition = nil
    }

    public mutating func cancel(deck: DeckID) {
        reset(deck: deck)
    }

    public mutating func cancelAll() {
        reset(deck: .a)
        reset(deck: .b)
        activeDeck = nil
        committedTransition = nil
        nextTransitionGeneration = checkedNext(after: nextTransitionGeneration)
    }

    /// Invalidates the committed/uncommitted transition timeline and resets the
    /// standby deck while leaving the active deck authoritative and unchanged.
    ///
    /// Used by seek (the smart-gap schedule was anchored to active-deck frame
    /// positions a seek moves) and by device recovery (after a `rebuildOutputPath()`
    /// the prior committed plan's frame anchors are meaningless, but the active
    /// deck's identity must survive the rebuild). The active deck keeps its phase,
    /// entry, and generation; only the *other* deck and the committed transition
    /// are discarded. Returns the deck that remained active (if any).
    @discardableResult
    public mutating func invalidateTimelinesPreservingActive() -> DeckID? {
        committedTransition = nil
        nextTransitionGeneration = checkedNext(after: nextTransitionGeneration)
        if let active = activeDeck {
            reset(deck: active.other)
            // `reset(deck:)` clears `committedTransition` (already nil here) but
            // never touches `activeDeck` for a non-active deck, so the active
            // deck's snapshot and `activeDeck` itself are preserved.
            return active
        }
        // No active deck (e.g. recovery while stopped) — invalidate both so no
        // stale standby survives the rebuild.
        reset(deck: .a)
        reset(deck: .b)
        return nil
    }

    @discardableResult
    public mutating func invalidateStandby(unlessEntryID expectedID: ID) -> Bool {
        guard let standby = activeDeck?.other ?? decks.indices.first(where: { decks[$0].phase != .empty }).map(deck(at:)),
              self[standby].entryID != expectedID else { return false }
        reset(deck: standby)
        return true
    }

    public func matches(deck: DeckID, entryID: ID, generation: UInt64, phase: DeckPhase? = nil) -> Bool {
        let snapshot = self[deck]
        return snapshot.entryID == entryID && snapshot.generation == generation && (phase == nil || snapshot.phase == phase)
    }

    private func index(of deck: DeckID) -> Int { deck == .a ? 0 : 1 }
    private func deck(at index: Int) -> DeckID { index == 0 ? .a : .b }
    private func checkedNext(after generation: UInt64) -> UInt64 {
        guard let next = DualDeckGeneration.next(after: generation) else {
            preconditionFailure("Dual-deck generation exhausted")
        }
        return next
    }
}

/// Frame-domain plan anchoring the outgoing deck's hard cut and the incoming
/// deck's start to one shared common-output timeline.
///
/// All frame positions are expressed in the common-output sample clock so two
/// independently prepared `AVAudioPlayerNode`s can be scheduled against a single
/// `AVAudioTime` anchor. `startIncomingAtFrame` equals `cutOutgoingAtFrame` plus
/// the injected (deliberate) gap; with zero injected frames the incoming deck
/// begins on the exact frame the outgoing deck is cut.
public struct DualDeckSchedule: Equatable, Sendable {
    public let cutOutgoingAtFrame: AVAudioFramePosition
    public let startIncomingAtFrame: AVAudioFramePosition
    public let injectedFrames: AVAudioFrameCount
    public let sampleRate: Double

    public init(
        cutOutgoingAtFrame: AVAudioFramePosition,
        startIncomingAtFrame: AVAudioFramePosition,
        injectedFrames: AVAudioFrameCount,
        sampleRate: Double
    ) {
        self.cutOutgoingAtFrame = cutOutgoingAtFrame
        self.startIncomingAtFrame = startIncomingAtFrame
        self.injectedFrames = injectedFrames
        self.sampleRate = sampleRate
    }

    /// Converts a deliberate gap measured in seconds to whole common-output
    /// frames. Non-finite or negative inputs yield zero injected frames.
    public static func injectedFrames(
        forSeconds seconds: Double,
        sampleRate: Double
    ) -> AVAudioFrameCount {
        guard seconds.isFinite, seconds > 0, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        let frames = (seconds * sampleRate).rounded()
        guard frames.isFinite, frames > 0, frames <= Double(AVAudioFrameCount.max) else { return 0 }
        return AVAudioFrameCount(frames)
    }

    /// Commits a sample-accurate transition plan, anchoring both decks to the
    /// `decodedEndFrame` of the outgoing deck on the common-output clock.
    ///
    /// Returns `nil` — rejecting the commitment — when:
    /// - the committed transition no longer matches the requested current/next
    ///   identity (a stale reorder/removal raced the commit),
    /// - the live `settingsRevision` advanced past the transition's snapshot (a
    ///   gap-only or plugin setting changed after standby preparation), or
    /// - the incoming deck is not yet `.ready`/`.scheduled` (deck B is late;
    ///   the caller must enter the degraded waiting state instead).
    ///
    /// No file open, reconnect, ReplayGain, plugin configuration, or engine stop
    /// may occur after this returns a non-nil plan — every expensive operation
    /// must already be complete by standby preparation.
    public static func commit<ID: Equatable & Sendable>(
        transition: DualDeckTransition<ID>?,
        currentID: ID,
        nextID: ID,
        incomingPhase: DeckPhase,
        liveSettingsRevision: UInt64,
        injectedSeconds: Double,
        decodedEndFrame: AVAudioFramePosition,
        sampleRate: Double
    ) -> DualDeckSchedule? {
        guard let transition,
              transition.currentID == currentID,
              transition.nextID == nextID else { return nil }
        guard transition.settingsRevision == liveSettingsRevision else { return nil }
        guard incomingPhase == .scheduled || incomingPhase == .ready else { return nil }
        guard sampleRate.isFinite, sampleRate > 0, decodedEndFrame >= 0 else { return nil }

        let injected = injectedFrames(forSeconds: injectedSeconds, sampleRate: sampleRate)
        return DualDeckSchedule(
            cutOutgoingAtFrame: decodedEndFrame,
            startIncomingAtFrame: decodedEndFrame + AVAudioFramePosition(injected),
            injectedFrames: injected,
            sampleRate: sampleRate
        )
    }
}
