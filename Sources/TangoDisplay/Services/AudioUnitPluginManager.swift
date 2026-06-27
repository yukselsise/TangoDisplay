import AVFoundation
import OSLog
import TangoDisplayCore

enum AudioUnitPluginError: Error, LocalizedError {
    case componentNotFound
    case instantiationFailed(String)
    case graphConnectionFailed(String)
    case uiUnavailable
    case invalidConfiguration(String)
    case presetUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .componentNotFound:           return "Audio Unit component not found on this Mac."
        case .instantiationFailed(let r):  return "Audio Unit instantiation failed: \(r)"
        case .graphConnectionFailed(let r): return "Audio graph connection failed: \(r)"
        case .uiUnavailable:               return "This plugin does not provide an editor UI."
        case .invalidConfiguration(let r): return "Plugin configuration is invalid: \(r)"
        case .presetUnavailable(let name): return "Plugin preset is unavailable: \(name)"
        }
    }
}

final class AudioUnitPluginManager {

    /// A plugin instance owned by one playback deck. This deliberately carries
    /// no editor-window or UI observation state: preparing a standby deck must
    /// not publish status or mutate the active deck's controls.
    struct DeckPluginRuntime {
        let slotID: UUID
        let selection: AudioUnitPluginSelection
        let unit: AVAudioUnit
        let isEnabled: Bool
        let configurationID: UUID?
    }

    func instantiateDeckChain(
        slots: [AudioUnitChainSlot],
        configuration: PluginChainConfiguration?
    ) async throws -> [DeckPluginRuntime] {
        var result: [DeckPluginRuntime] = []
        result.reserveCapacity(slots.count)

        for slot in slots {
            try Task.checkCancellation()
            let unit = try await instantiate(slot.selection)
            try Task.checkCancellation()

            let configuredState = configuration?.slotStates.first { $0.slotID == slot.id }
            if let configuredState,
               configuredState.componentSubType != slot.selection.componentSubType {
                throw AudioUnitPluginError.invalidConfiguration(
                    "\(slot.selection.name): component type does not match the assigned slot"
                )
            }
            if let configuredState {
                let fullState: [String: Any]
                do {
                    fullState = try AUStateCodec.decode(configuredState.auState)
                } catch {
                    throw AudioUnitPluginError.invalidConfiguration(
                        "\(slot.selection.name): \(error.localizedDescription)"
                    )
                }
                unit.auAudioUnit.fullState = fullState
            } else if configuration == nil, let presetName = slot.lastUsedPresetName {
                let presetManager = AudioUnitPresetManager(for: slot.selection)
                let presets = presetManager.factoryPresets(for: unit) + presetManager.userPresets()
                guard let preset = presets.first(where: { $0.name == presetName }) else {
                    throw AudioUnitPluginError.presetUnavailable(presetName)
                }
                try presetManager.applyPreset(preset, to: unit)
            }
            unit.auAudioUnit.shouldBypassEffect = !(configuredState?.isEnabled ?? slot.isEnabled)

            result.append(DeckPluginRuntime(
                slotID: slot.id,
                selection: slot.selection,
                unit: unit,
                isEnabled: configuredState?.isEnabled ?? slot.isEnabled,
                configurationID: configuration?.id
            ))
        }
        return result
    }

    func availableEffects() -> [AudioUnitPluginSelection] {
        // Enumerate both plain effects (aufx) and music effects (aumf). Many
        // modern plugins (e.g. FabFilter Pro-Q 4) register as aumf so they can
        // accept MIDI input; they still process audio like any other effect in
        // an AVAudioEngine chain (MIDI is optional), so they belong here.
        // Instruments (aumu) are deliberately excluded — they are synths.
        let manager = AVAudioUnitComponentManager.shared()
        let effectTypes: [OSType] = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]
        let components = effectTypes.flatMap { type -> [AVAudioUnitComponent] in
            let desc = AudioComponentDescription(
                componentType: type,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            return manager.components(matching: desc)
        }
        return components
            .map { component in
                AudioUnitPluginSelection(
                    id: UUID(),
                    name: component.name,
                    manufacturerName: component.manufacturerName,
                    componentType: component.audioComponentDescription.componentType,
                    componentSubType: component.audioComponentDescription.componentSubType,
                    componentManufacturer: component.audioComponentDescription.componentManufacturer
                )
            }
            .sorted { ($0.manufacturerName, $0.name) < ($1.manufacturerName, $1.name) }
    }

    func isAvailable(_ selection: AudioUnitPluginSelection) -> Bool {
        let desc = AudioComponentDescription(
            componentType: OSType(selection.componentType),
            componentSubType: OSType(selection.componentSubType),
            componentManufacturer: OSType(selection.componentManufacturer),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return !AVAudioUnitComponentManager.shared().components(matching: desc).isEmpty
    }

    func instantiate(_ selection: AudioUnitPluginSelection) async throws -> AVAudioUnit {
        let desc = AudioComponentDescription(
            componentType: OSType(selection.componentType),
            componentSubType: OSType(selection.componentSubType),
            componentManufacturer: OSType(selection.componentManufacturer),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let components = AVAudioUnitComponentManager.shared().components(matching: desc)
        guard !components.isEmpty else {
            throw AudioUnitPluginError.componentNotFound
        }

        // Hosting mode: default to out-of-process (OOP). OOP is Apple's
        // standard hosting path — it isolates plugin crashes inside the AU's
        // own process and is what 3rd-party plugins are tested against. Some
        // V2 plugins (e.g. FabFilter Pro-Q 4) crash the *host* outright when
        // their editor is created in-process via the V2→V3 bridge, so loading
        // them in-process is unsafe.
        //
        // Exception: the in-process allowlist below. A few V2 plugins only
        // relay UI resize events to the host when loaded *in-process*; under
        // the OOP V2→V3 bridge their view is wrapped in NSRemoteView, which
        // doesn't surface remote-side frame changes, so plugin-driven window
        // resizing (e.g. MJUC's expander) silently breaks. For those we load
        // in-process and accept the lack of crash isolation.
        let key = ComponentKey(manufacturer: selection.componentManufacturer,
                               subType: selection.componentSubType)
        let loadInProcess = Self.inProcessAllowlist.contains(key)

        let primary: AudioComponentInstantiationOptions = loadInProcess ? [] : .loadOutOfProcess
        let fallback: AudioComponentInstantiationOptions = loadInProcess ? .loadOutOfProcess : []

        if let unit = await Self.tryInstantiate(desc: desc, options: primary) {
            return unit
        }
        if let unit = await Self.tryInstantiate(desc: desc, options: fallback) {
            return unit
        }
        throw AudioUnitPluginError.instantiationFailed("instantiation returned nil")
    }

    // MARK: - In-process hosting allowlist

    private struct ComponentKey: Hashable {
        let manufacturer: UInt32
        let subType: UInt32
    }

    /// V2 plugins that must load in-process for plugin-driven window resize
    /// to work. Loaded out-of-process their editor is wrapped in NSRemoteView,
    /// which swallows the frame-change events the host needs to grow the
    /// window. Keyed on (manufacturer, subType) four-char codes. Keep this
    /// list as small as possible — in-process plugins are not crash-isolated.
    private static let inProcessAllowlist: Set<ComponentKey> = [
        // Klanghelm MJUC — its expander panel grows the editor at runtime.
        ComponentKey(manufacturer: fourCharCode("KlHm"), subType: fourCharCode("MJUC")),
    ]

    /// Convert a four-character code string (e.g. "KlHm") to the OSType/
    /// FourCharCode value AudioComponentDescription uses.
    private static func fourCharCode(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func tryInstantiate(
        desc: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async -> AVAudioUnit? {
        await withCheckedContinuation { continuation in
            AVAudioUnit.instantiate(with: desc, options: options) { avUnit, _ in
                continuation.resume(returning: avUnit)
            }
        }
    }
}
