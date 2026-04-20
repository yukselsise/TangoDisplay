import SwiftUI
import TangoDisplayCore

struct IdleView: View {
    let mode: DisplayMode
    @ObservedObject var settings: AppSettings
    let profile: AppearanceProfile

    var body: some View {
        ZStack {
            // Idle message
            if !settings.idleMessage.isEmpty {
                Text(settings.idleMessage)
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(profile.artistSwiftUIColor.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding()
            }

            // Paused banner
            if mode == .paused {
                VStack {
                    HStack {
                        Text("PAUSED")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Spacer()
                    }
                    .padding(20)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
