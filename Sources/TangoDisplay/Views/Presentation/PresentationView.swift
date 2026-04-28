import AppKit
import SwiftUI
import TangoDisplayCore

struct PresentationView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    var isPreview: Bool = false

    @State private var bgImage: NSImage? = nil

    private var activeProfile: AppearanceProfile {
        if let draft = appState.draftProfile { return draft }
        let all = appState.profileStore.allProfiles
        if let id = appState.settings.activeProfileID,
           let found = all.first(where: { $0.id == id }) {
            return found
        }
        return AppearanceProfile.classic
    }

    var body: some View {
        // Content layer: transitions between playing/idle/cortina views.
        // Background is applied behind it; track counter is overlaid on top.
        ZStack {
            // Album artwork layer — above background, below text.
            // Uses displayedArtworkTrackID as transition identity so it
            // transitions in/out with each track change (same timing as text).
            if activeProfile.showAlbumArtwork {
                TransitionContainer(
                    identity: appState.displayedArtworkTrackID,
                    style: activeProfile.transitionStyle,
                    duration: activeProfile.transitionDuration
                ) {
                    if let art = appState.currentArtwork {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(activeProfile.albumArtworkScale)
                            .offset(x: activeProfile.albumArtworkOffsetX,
                                    y: activeProfile.albumArtworkOffsetY)
                            .opacity(activeProfile.albumArtworkOpacity)
                    }
                }
            }

            TransitionContainer(
                identity: appState.displayState,
                style: activeProfile.transitionStyle,
                duration: activeProfile.transitionDuration
            ) {
                contentView
            }

            // Window registration (real display only)
            if !isPreview {
                WindowAccessor { WindowManager.register($0) }
                    .allowsHitTesting(false)
            }
        }
        .background {
            // Rendered behind the content by SwiftUI's layout contract —
            // .background() can never cover its parent view.
            ZStack {
                activeProfile.backgroundSwiftUIColor
                    .ignoresSafeArea()

                if let img = bgImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(activeProfile.backgroundImageScale)
                        .offset(x: activeProfile.backgroundImageOffsetX,
                                y: activeProfile.backgroundImageOffsetY)
                        .opacity(activeProfile.backgroundImageOpacity)
                        .clipped()
                        .ignoresSafeArea()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            // Track counter — in an overlay so it is always in front by
            // SwiftUI's layout contract, regardless of background image
            // rendering. Toggle takes effect instantly; shown only when .playing
            // and a position is available (always true for dance tracks).
            // Shows "Track N of M" when the full playlist is known (Music.app,
            // Embrace), or "Track N" from history alone (Swinsian).
            if settings.showTrackCounter,
               appState.displayState.mode == .playing,
               let pos = appState.displayState.tandaPosition {
                Text(tandaLabel(pos))
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(activeProfile.trackCounterSwiftUIColor)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { reloadBgImage() }
        .onChange(of: activeProfile) { _ in reloadBgImage() }
    }

    private func reloadBgImage() {
        guard let filename = activeProfile.backgroundImageFilename else {
            bgImage = nil
            return
        }
        let url = appState.profileStore.imageURL(for: filename)
        bgImage = NSImage(contentsOf: url)
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.displayState.mode {
        case .playing:
            PlayingView(
                state: appState.displayState,
                profile: activeProfile
            )
        case .cortina:
            CortinaView(
                state: appState.displayState,
                profile: activeProfile,
                settings: appState.settings
            )
        case .idle, .paused:
            IdleView(
                mode: appState.displayState.mode,
                settings: appState.settings,
                profile: activeProfile
            )
        case .override:
            overrideView
        }
    }

    private func tandaLabel(_ pos: TandaPosition) -> String {
        if let total = pos.total {
            return "Track \(pos.current) of \(total)"
        } else {
            return "Track \(pos.current)"
        }
    }

    private var overrideView: some View {
        Text(appState.displayState.overrideText ?? "")
            .font(.system(size: 72, weight: .light))
            .foregroundColor(activeProfile.titleSwiftUIColor)
            .multilineTextAlignment(.center)
            .padding(60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
