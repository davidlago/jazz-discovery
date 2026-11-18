import AppIntents
import Foundation

/// Plays the next stop on the path you're on (Siri, Shortcuts, and the Continue widget's play button). It's in the
/// widget extension too, so the widget's button can name it, but it always runs in the app, where the player is.
struct PlayNextStopIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Next Stop"
    static let description = IntentDescription("Plays the next stop on the path you're on.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXTENSION
        return .result(dialog: "Open Jazz Discovery to continue.")
        #else
        let ctx = AppContext.shared
        guard let passport = ctx.passport, let player = ctx.player else {
            return .result(dialog: "Open Jazz Discovery once, then try again.")
        }
        switch PathPlayback.playNext(library: ctx.lib, passport: passport, player: player) {
        case .playing(let title): return .result(dialog: "Playing \(title).")
        case .notPlayable(let title): return .result(dialog: "Your next stop is \(title). Open Jazz Discovery to read it.")
        case .noPath: return .result(dialog: "You're not on a path yet. Start Here is a good one.")
        }
        #endif
    }
}
