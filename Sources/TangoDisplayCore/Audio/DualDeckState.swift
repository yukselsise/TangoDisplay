public enum DeckID: String, CaseIterable, Sendable {
    case a
    case b

    public var other: DeckID { self == .a ? .b : .a }
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

public struct DualDeckTransition<ID: Sendable & Equatable>: Sendable, Equatable {
    public let outgoingDeck: DeckID
    public let incomingDeck: DeckID
    public let currentID: ID
    public let nextID: ID
    public let generation: UInt64
    public let settingsRevision: UInt64

    public init(
        outgoingDeck: DeckID,
        incomingDeck: DeckID,
        currentID: ID,
        nextID: ID,
        generation: UInt64,
        settingsRevision: UInt64
    ) {
        self.outgoingDeck = outgoingDeck
        self.incomingDeck = incomingDeck
        self.currentID = currentID
        self.nextID = nextID
        self.generation = generation
        self.settingsRevision = settingsRevision
    }
}

public struct DualDeckState<ID: Sendable & Equatable>: Sendable {
    private var decks: [DeckSnapshot<ID>]
    public private(set) var activeDeck: DeckID?
    public private(set) var committedTransition: DualDeckTransition<ID>?

    public init() {
        decks = [DeckSnapshot(), DeckSnapshot()]
    }

    public subscript(deck: DeckID) -> DeckSnapshot<ID> {
        decks[index(of: deck)]
    }

    public mutating func activate(deck: DeckID, entryID: ID, generation: UInt64) {
        decks[index(of: deck)] = DeckSnapshot(phase: .active, entryID: entryID, generation: generation)
        activeDeck = deck
        committedTransition = nil
    }

    @discardableResult
    public mutating func beginPreparation(
        deck: DeckID,
        entryID: ID,
        generation: UInt64,
        automaticTransitionAllowed: Bool = true
    ) -> Bool {
        guard automaticTransitionAllowed, deck != activeDeck else { return false }
        decks[index(of: deck)] = DeckSnapshot(phase: .preparing, entryID: entryID, generation: generation)
        committedTransition = nil
        return true
    }

    @discardableResult
    public mutating func markReady(deck: DeckID, entryID: ID, generation: UInt64) -> Bool {
        guard matches(deck: deck, entryID: entryID, generation: generation, phase: .preparing) else { return false }
        decks[index(of: deck)].phase = .ready
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
              next.entryID == nextID,
              current.generation == next.generation else { return nil }
        let token = DualDeckTransition(
            outgoingDeck: outgoing,
            incomingDeck: incoming,
            currentID: currentID,
            nextID: nextID,
            generation: current.generation,
            settingsRevision: settingsRevision
        )
        decks[index(of: incoming)].phase = .scheduled
        committedTransition = token
        return token
    }

    public mutating func promote(_ token: DualDeckTransition<ID>) -> DeckID? {
        promote(token, settingsRevision: token.settingsRevision)
    }

    public mutating func promote(_ token: DualDeckTransition<ID>, settingsRevision: UInt64) -> DeckID? {
        guard committedTransition == token,
              token.settingsRevision == settingsRevision,
              activeDeck == token.outgoingDeck,
              matches(deck: token.outgoingDeck, entryID: token.currentID, generation: token.generation, phase: .active),
              matches(deck: token.incomingDeck, entryID: token.nextID, generation: token.generation, phase: .scheduled)
        else { return nil }
        decks[index(of: token.outgoingDeck)].phase = .recycling
        decks[index(of: token.incomingDeck)].phase = .active
        activeDeck = token.incomingDeck
        committedTransition = nil
        return token.incomingDeck
    }

    @discardableResult
    public mutating func invalidateStandby(unlessEntryID expectedID: ID) -> Bool {
        guard let standby = activeDeck?.other ?? decks.indices.first(where: { decks[$0].phase != .empty }).map(deck(at:)),
              self[standby].entryID != expectedID else { return false }
        decks[index(of: standby)] = DeckSnapshot()
        committedTransition = nil
        return true
    }

    public func matches(deck: DeckID, entryID: ID, generation: UInt64, phase: DeckPhase? = nil) -> Bool {
        let snapshot = self[deck]
        return snapshot.entryID == entryID && snapshot.generation == generation && (phase == nil || snapshot.phase == phase)
    }

    private func index(of deck: DeckID) -> Int { deck == .a ? 0 : 1 }
    private func deck(at index: Int) -> DeckID { index == 0 ? .a : .b }
}
