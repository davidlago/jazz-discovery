import SwiftUI
import AppKit

/// The listening guides' times, taken by ear: play the recording with Apple Music and press M as each section starts.
///
/// Hidden unless the app is launched with `-guideEditor YES` (scripts/guide-editor.sh). Edits apply to the running
/// app at once (the guide page follows the new times), are kept in the app's container between launches, and go back
/// to the repository as guides.json through Copy JSON.
@MainActor
@Observable
final class GuideEditorModel {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "guideEditor") }

    let library: JazzLibrary
    private(set) var guides: [Guide]
    var selectedID: String?
    var selection = 0
    var message = ""

    init(library: JazzLibrary) {
        self.library = library
        Self.applySaved(to: library)
        guides = library.guides
        selectedID = guides.first?.id
    }

    /// Puts the editor's saved work into the library, so guide pages follow it from launch. A saved guide wins when it's
    /// fully timed, or when the bundled one isn't timed either (work in progress); a saved guide that's untimed or half
    /// timed doesn't hide times the bundle has since. Guides added to the bundle since are kept, and saved ones it has
    /// dropped go.
    static func applySaved(to library: JazzLibrary) {
        guard let saved = loadSaved() else { return }
        let byID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        library.guides = library.guides.map { bundled in
            guard let mine = byID[bundled.id], mine.isTimed || !bundled.isTimed else { return bundled }
            return mine
        }
    }

    var guide: Guide? { guides.first { $0.id == selectedID } }
    var guideIndex: Int? { guides.firstIndex { $0.id == selectedID } }

    // MARK: Editing

    private func update(_ change: (inout Guide) -> Void) {
        guard let i = guideIndex else { return }
        change(&guides[i])
        library.guides = guides
        save()
    }

    func set(_ i: Int, _ change: (inout GuideSection) -> Void) {
        update { g in if g.sections.indices.contains(i) { change(&g.sections[i]) } }
    }

    /// Takes the time for the selected section from the player, and moves to the next one.
    func stamp(_ player: PlayerController) {
        guard let g = guide else { return }
        guard player.isPlaying(g, library: library), player.usingAppleMusic else {
            message = "Play the recording with Apple Music first (Play from the start)."
            return
        }
        let t = (player.position() * 10).rounded() / 10
        let i = selection
        update { g in
            g.sections[i].at = i == 0 && t < 1.5 ? 0 : t
            g.songID = player.currentTrackID
            g.duration = (player.duration * 10).rounded() / 10
        }
        message = "\(g.sections[i].label) at \(GuideTime.text(t))"
        if selection + 1 < g.sections.count { selection += 1 }
    }

    func nudge(_ seconds: Double) {
        guard let at = guide?.sections[safe: selection]?.at else { return }
        let t = max(0, ((at + seconds) * 10).rounded() / 10)
        set(selection) { $0.at = t }
        message = "\(guide?.sections[selection].label ?? "") at \(GuideTime.text(t)) (\(String(format: "%.1f", t)) s)"
    }

    /// Plays from just before the selected section's time, to hear whether it lands.
    func replay(_ player: PlayerController) {
        guard let g = guide, let at = g.sections[safe: selection]?.at, player.isPlaying(g, library: library) else { return }
        player.seek(toSeconds: max(0, at - 2))
        if !player.isPlaying { player.togglePlayPause() }
    }

    func addSection(_ player: PlayerController) {
        guard let g = guide else { return }
        let t = player.isPlaying(g, library: library) ? (player.position() * 10).rounded() / 10 : nil
        let i = min(selection + 1, g.sections.count)
        update { $0.sections.insert(GuideSection(at: t, kind: .solo, label: "New section", note: ""), at: i) }
        selection = i
    }

    func deleteSection() {
        guard let g = guide, g.sections.count > 1 else { return }
        let i = selection
        update { $0.sections.remove(at: i) }
        selection = min(i, g.sections.count - 2)
    }

    func clearTimes() {
        update { g in
            for i in g.sections.indices { g.sections[i].at = nil }
            g.songID = nil; g.duration = nil
        }
        selection = 0
        message = "Times cleared."
    }

    func revertToBundled() {
        guard let id = selectedID, let bundled = JazzLibrary.optional(GuidesData.self, "guides", in: .main)?.guides.first(where: { $0.id == id })
        else { return }
        update { $0 = bundled }
        selection = 0
        message = "Back to the guide as it ships."
    }

    // MARK: Saving

    var json: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(GuidesData(guides: guides)) else { return "" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        message = "guides.json is on the clipboard (and saved at \(Self.file.path))."
    }

    static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jazz Discovery", isDirectory: true)
        return dir.appendingPathComponent("guides-edited.json")
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: Self.file, options: .atomic)
    }

    private static func loadSaved() -> [Guide]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(GuidesData.self, from: data).guides
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Opens the editor from the Playback menu.
struct GuideEditorMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Guide Editor…") { openWindow(id: GuideEditorView.windowID) }
            .keyboardShortcut("g", modifiers: [.command, .option])
    }
}

struct GuideEditorView: View {
    static let windowID = "guide-editor"
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var model: GuideEditorModel?
    @FocusState private var timingFocus: Bool

    var body: some View {
        Group {
            if let model { editor(model) } else { ProgressView() }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Theme.ink)
        .onAppear { if model == nil { model = GuideEditorModel(library: library) } }
    }

    private func editor(_ m: GuideEditorModel) -> some View {
        @Bindable var m = m
        return HStack(spacing: 0) {
            List(selection: $m.selectedID) {
                ForEach(m.guides) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.tracks[g.track]?.title ?? g.id).font(.system(size: 13, weight: .semibold))
                        Text(g.isTimed ? "Timed" : "\(g.sections.filter { $0.at != nil }.count) of \(g.sections.count) timed")
                            .font(.system(size: 11)).foregroundStyle(g.isTimed ? .green : .secondary)
                    }
                    .tag(Optional(g.id))
                }
            }
            .frame(width: 220)
            .onChange(of: m.selectedID) { m.selection = 0; m.message = "" }

            Divider()

            if let g = m.guide { detail(m, g) } else { Spacer() }
        }
    }

    private func detail(_ m: GuideEditorModel, _ g: Guide) -> some View {
        let playing = player.isPlaying(g, library: library)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(library.tracks[g.track]?.title ?? g.id).font(Theme.display(34)).foregroundStyle(Theme.cream)
                Text(library.tracks[g.track]?.artistName ?? "").foregroundStyle(Theme.muted)
                Spacer()
                TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying)) { ctx in
                    Text(playing ? String(format: "%@  ·  %.1f s", GuideTime.text(player.position(at: ctx.date)), player.position(at: ctx.date)) : "—")
                        .font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.brass)
                }
            }
            HStack(spacing: 10) {
                Button("Play from the start") {
                    if let t = library.tracks[g.track] { player.play(t.track) }
                    timingFocus = true
                }
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause(); timingFocus = true }.disabled(!playing)
                Text(playing ? (player.usingAppleMusic ? "Full track, Apple Music" : "Preview: times can't be taken")
                     : "Not playing").font(.system(size: 12)).foregroundStyle(playing && player.usingAppleMusic ? .green : .orange)
                Spacer()
                Button("Copy JSON") { m.copyJSON() }
                Menu("More") {
                    Button("Clear all times") { m.clearTimes() }
                    Button("Back to the guide as it ships") { m.revertToBundled() }
                }
                .fixedSize()
            }
            FormBar(guide: g, synced: player.sync(for: g, library: library) == .following, height: 26) { i in
                m.selection = i
                if let at = g.sections[i].at, playing { player.seek(toSeconds: at) }
            }
            Text("Space play/pause · M time the selected section (then moves on) · ←/→ nudge 0.5 s · ⇧←/⇧→ nudge 0.1 s · R replay from 2 s before · ↑/↓ select")
                .font(.system(size: 11)).foregroundStyle(Theme.faint)

            HStack(alignment: .top, spacing: 14) {
                sectionList(m, g)
                sectionDetail(m, g).frame(width: 340)
            }
            Text(m.message).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .padding(18)
    }

    private func sectionList(_ m: GuideEditorModel, _ g: Guide) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(g.sections.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 10) {
                            Text(s.at.map { String(format: "%@ (%.1f)", GuideTime.text($0), $0) } ?? "—")
                                .font(.system(size: 12).monospacedDigit()).frame(width: 90, alignment: .leading)
                                .foregroundStyle(s.at == nil ? Theme.faint : Theme.cream)
                            Text(s.kind.label.uppercased()).font(Theme.label(9)).foregroundStyle(Theme.muted).frame(width: 70, alignment: .leading)
                            Text(s.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i == m.selection ? Theme.brass.opacity(0.25) : Theme.panel))
                        .contentShape(Rectangle())
                        .onTapGesture { m.selection = i; timingFocus = true }
                        .id(i)
                    }
                }
            }
            .onChange(of: m.selection) { _, i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
        .focusable()
        .focused($timingFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handle(press, m, g) }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(timingFocus ? Theme.brass.opacity(0.6) : Theme.panelHi))
        .onAppear { timingFocus = true }
    }

    private func handle(_ press: KeyPress, _ m: GuideEditorModel, _ g: Guide) -> KeyPress.Result {
        let fine = press.modifiers.contains(.shift)
        switch press.key {
        case .space: player.togglePlayPause(); return .handled
        case .leftArrow: m.nudge(fine ? -0.1 : -0.5); return .handled
        case .rightArrow: m.nudge(fine ? 0.1 : 0.5); return .handled
        case .upArrow: m.selection = max(0, m.selection - 1); return .handled
        case .downArrow: m.selection = min(g.sections.count - 1, m.selection + 1); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "m": m.stamp(player); return .handled
        case "r": m.replay(player); return .handled
        default: return .ignored
        }
    }

    private func sectionDetail(_ m: GuideEditorModel, _ g: Guide) -> some View {
        let i = m.selection
        let s = g.sections[safe: i]
        return VStack(alignment: .leading, spacing: 8) {
            if let s {
                Picker("Kind", selection: Binding(get: { s.kind }, set: { k in m.set(i) { $0.kind = k } })) {
                    ForEach(GuideSection.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Label", text: Binding(get: { s.label }, set: { v in m.set(i) { $0.label = v } }))
                TextField("Who (artist IDs or names, commas)", text: Binding(
                    get: { s.who.joined(separator: ", ") },
                    set: { v in m.set(i) { $0.who = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }))
                Text("Note").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { s.note }, set: { v in m.set(i) { $0.note = v } }))
                    .font(.system(size: 13)).frame(minHeight: 140)
                    .scrollContentBackground(.hidden).background(Theme.panel)
                HStack {
                    Button("Add section after") { m.addSection(player) }
                    Button("Delete") { m.deleteSection() }.disabled(g.sections.count < 2)
                    Spacer()
                    Button("Clear time") { m.set(i) { $0.at = nil } }.disabled(s.at == nil)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
