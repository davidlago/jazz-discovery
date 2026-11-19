import SwiftUI
import Observation

/// A round of the Blindfold Test in progress.
@MainActor
@Observable
final class BlindfoldGame {
    private(set) var questions: [BlindQuestion] = []
    private(set) var index = 0
    private(set) var picked: String?
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var best = 0
    private(set) var missed: [BlindQuestion] = []
    /// For "which came first?": which of the two clips is playing.
    private(set) var playingSecond = false
    var level: BlindLevel = .easy
    var focus: String?

    var current: BlindQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    var finished: Bool { !questions.isEmpty && index >= questions.count }
    var started: Bool { !questions.isEmpty }

    func start(library: JazzLibrary, player: PlayerController) {
        questions = RoundMaker.round(level: level, library: library, seed: UInt64.random(in: 1...UInt64.max), focus: focus)
        index = 0; picked = nil; score = 0; streak = 0; best = 0; missed = []
        play(player)
    }

    func play(_ player: PlayerController) {
        guard let q = current else { return }
        playingSecond = false
        player.playBlind(q.clip.track)
    }

    func playSecond(_ player: PlayerController) {
        guard let q = current, let s = q.second else { return }
        playingSecond = true
        player.playBlind(s.track)
    }

    func answer(_ choice: String, passport: Passport, library: JazzLibrary) {
        guard let q = current, picked == nil else { return }
        picked = choice
        let right = choice == q.answer
        if right { score += 1; streak += 1; best = max(best, streak) } else { streak = 0; missed.append(q) }
        if let era = RoundMaker.eraOf(q.clip, library) { passport.recordAnswer(era: era, right: right) }
    }

    func next(_ player: PlayerController) {
        index += 1; picked = nil
        if finished { player.stop() } else { play(player) }
    }

    func quit(_ player: PlayerController) {
        if player.isBlind { player.stop() }
        questions = []; index = 0; picked = nil
    }
}

/// The game: pick a level (and an era, if you like), then ten clips under a hidden sleeve.
struct BlindfoldView: View {
    var compact = false
    var openAlbum: (String) -> Void
    @State private var game = BlindfoldGame()
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        Group {
            if compact {
                round
            } else {
                // On the Mac, how your ear is doing sits beside the game, and fills in as you answer.
                SideColumnLayout(sideWidth: 300) {
                    round
                    EarPanel()
                }
            }
        }
        .onDisappear { game.quit(player) }
    }

    @ViewBuilder private var round: some View {
        if game.finished { results }
        else if let q = game.current { question(q) }
        else { setup }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Ten clips. The cover stays hidden until you answer: which era, who's playing, which instrument leads, which came first. No timer.")
                .font(.scaled(size: compact ? 15 : 17, design: .serif)).italic().foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("LEVEL").font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.muted)
                Picker("Level", selection: $game.level) {
                    ForEach(BlindLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ERAS").font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.muted)
                Picker("Eras", selection: $game.focus) {
                    Text("Every era").tag(String?.none)
                    ForEach(library.eras.filter { RoundMaker.clips(library: library, focus: $0.id).count >= 14 }) { e in
                        Text(e.name).tag(Optional(e.id))
                    }
                }
                .labelsHidden().fixedSize()
            }
            Button { game.start(library: library, player: player) } label: {
                Label("Start", systemImage: "play.fill").font(.scaled(size: 16, weight: .bold))
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(RoundMaker.clips(library: library).count < 20)
            if let ear = passport.earSummary(library: library) {
                Text(ear).font(.scaled(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: A question

    private func question(_ q: BlindQuestion) -> some View {
        let answered = game.picked != nil
        let sleeve: CGFloat = compact ? 240 : 300
        return VStack(alignment: compact ? .center : .leading, spacing: 18) {
            HStack {
                Text("\(game.index + 1) OF \(game.questions.count)").font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(game.score) RIGHT\(game.streak > 1 ? " · STREAK \(game.streak)" : "")")
                    .font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.brass)
            }
            .frame(maxWidth: compact ? .infinity : 560)

            ZStack {
                if answered {
                    reveal(q).transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                } else {
                    BlindSleeve(playing: player.isBlind && player.isPlaying)
                        .transition(.opacity)
                }
            }
            .frame(width: sleeve, height: sleeve)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: answered)

            Text(q.prompt).font(Theme.display(compact ? 28 : 34)).foregroundStyle(Theme.cream)

            if q.kind == .whichFirst {
                HStack(spacing: 10) {
                    clipButton("First clip", active: !game.playingSecond) { game.play(player) }
                    clipButton("Second clip", active: game.playingSecond) { game.playSecond(player) }
                }
            } else {
                Button { game.play(player) } label: { Label("Play again", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.plain).font(.scaled(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .keyboardShortcut(.space, modifiers: [])
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(q.choices.enumerated()), id: \.element.id) { i, c in
                    Button { game.answer(c.id, passport: passport, library: library) } label: {
                        Text(c.label).font(.scaled(size: compact ? 15 : 15, weight: .semibold)).lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 46)
                            .padding(.horizontal, 10)
                            .foregroundStyle(color(for: c, q, text: true))
                            .background(RoundedRectangle(cornerRadius: 12).fill(color(for: c, q, text: false)))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(answered)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
            .frame(maxWidth: 560)
            .sensoryFeedback(trigger: game.picked) { _, new in
                guard let new else { return nil }
                return new == q.answer ? .success : .error
            }

            if answered {
                Button { game.next(player) } label: {
                    Text(game.index + 1 == game.questions.count ? "See Results" : "Next")
                        .font(.scaled(size: 15, weight: .bold)).padding(.horizontal, 24).padding(.vertical, 11)
                        .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private func clipButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: active && player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                .font(.scaled(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(active ? Theme.ink : Theme.cream)
                .background(Capsule().fill(active ? Theme.cream : Theme.panelHi))
        }
        .buttonStyle(.plain)
    }

    private func color(for c: BlindQuestion.Choice, _ q: BlindQuestion, text: Bool) -> Color {
        guard let picked = game.picked else { return text ? Theme.cream : Theme.panelHi }
        if c.id == q.answer { return text ? Theme.ink : Color(hex: "#7BC47F") }
        if c.id == picked { return text ? Theme.cream : Color(hex: "#C0504D") }
        return text ? Theme.faint : Theme.panel
    }

    /// The sleeve turned over: the cover, what it was, and why it matters.
    private func reveal(_ q: BlindQuestion) -> some View {
        let clips = [q.clip] + (q.second.map { [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(clips, id: \.id) { t in
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: t.track.artwork(400)) { Theme.panelHi }
                        .frame(width: clips.count > 1 ? 70 : 120, height: clips.count > 1 ? 70 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.scaled(size: 15, weight: .bold)).foregroundStyle(Theme.cream).lineLimit(2)
                        Text(t.artistName).font(.scaled(size: 13)).foregroundStyle(Theme.muted)
                        if let y = Programmer.year(t, library: library) {
                            Text(String(y)).font(.scaled(size: 12)).foregroundStyle(Theme.faint)
                        }
                        if let id = t.album {
                            Button("Open the record") { openAlbum(id) }.buttonStyle(.plain)
                                .font(.scaled(size: 12, weight: .semibold)).foregroundStyle(Theme.brass)
                        }
                    }
                }
            }
            if q.second == nil {
                Text(Programmer.reason(for: q.clip, library: library))
                    .font(.scaled(size: 12, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.85))
                    .lineLimit(5).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
    }

    // MARK: Results

    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(game.score) OF \(game.questions.count)").font(Theme.display(compact ? 54 : 72)).foregroundStyle(Theme.brass)
            Text(game.score >= 8 ? "Big ears." : game.score >= 5 ? "Good listening." : "Every listener starts somewhere.")
                .font(.scaled(size: 18, design: .serif)).italic().foregroundStyle(Theme.cream)
            if game.best > 2 { Text("Best streak: \(game.best)").font(.scaled(size: 13)).foregroundStyle(Theme.muted) }
            if !game.missed.isEmpty {
                Text("THE ONES THAT GOT AWAY").font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.muted)
                ForEach(game.missed) { q in
                    Button { if let id = q.clip.album { openAlbum(id) } else { player.play(q.clip.track) } } label: {
                        HStack(spacing: 10) {
                            RemoteImage(url: q.clip.track.artwork(200)) { Theme.panelHi }
                                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.clip.title).font(.scaled(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                                Text(q.clip.artistName).font(.scaled(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                Button { game.start(library: library, player: player) } label: {
                    Label("Play Again", systemImage: "arrow.clockwise").font(.scaled(size: 15, weight: .bold))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                Button("Change Level") { game.quit(player) }.buttonStyle(.plain).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// The hidden cover: a typographic sleeve with a big question mark and grooves that turn while the clip plays.
struct BlindSleeve: View {
    var playing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Theme.panel)
            Circle().fill(Color.black).padding(24)
                .overlay {
                    ForEach(0..<6) { i in
                        Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 1).padding(CGFloat(34 + i * 12))
                    }
                }
                .phaseAnimator([0.0, 360.0], trigger: playing) { v, angle in v.rotationEffect(.degrees(playing ? angle : 0)) }
                    animation: { _ in playing ? .linear(duration: 4) : .default }
            Text("?").font(Theme.display(140)).foregroundStyle(Theme.brass)
            VStack {
                Spacer()
                Text("BLINDFOLD TEST").font(Theme.label(10)).tracking(3).foregroundStyle(Theme.muted).padding(.bottom, 10)
            }
        }
        .accessibilityLabel("Hidden record")
    }
}

/// Your ear, era by era: how many of each era's clips you've placed, as a bar in its colour. Before any answers, what
/// the game asks.
struct EarPanel: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        let ears = passport.data.ears ?? [:]
        let scored = library.eras.compactMap { e in ears[e.id].map { (era: e, score: $0) } }.filter { $0.score.total > 0 }
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR EAR").font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.brass)
            if scored.isEmpty {
                Text("Every answer counts towards the era it came from, so after a round or two this shows which eras your ear knows and which need work.")
                    .font(.scaled(size: 13, design: .serif)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Which era is this?", "Who's playing?", "Which instrument leads?", "Which came first?"], id: \.self) { q in
                        Label(q, systemImage: "questionmark.circle").font(.scaled(size: 13)).foregroundStyle(Theme.cream.opacity(0.85))
                    }
                }
            } else {
                if let summary = passport.earSummary(library: library) {
                    Text(summary).font(.scaled(size: 14, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(scored, id: \.era.id) { row in
                    let f = Double(row.score.right) / Double(row.score.total)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.era.name).font(.scaled(size: 12, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                            Spacer()
                            Text("\(row.score.right) of \(row.score.total)").font(.scaled(size: 11)).monospacedDigit()
                                .foregroundStyle(Theme.muted)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.panelHi)
                                Capsule().fill(row.era.tint).frame(width: max(4, geo.size.width * f))
                            }
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.era.name): \(row.score.right) of \(row.score.total) right")
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
    }
}
