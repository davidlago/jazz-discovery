import SwiftUI
import UserNotifications

/// The optional morning note: the day's lead from Today in Jazz, at a time you pick. Off unless turned on; the
/// permission prompt appears only then. Local only: the next seven days are scheduled on the device and refreshed each
/// time the app opens. No server, no push.
@MainActor
@Observable
final class MorningNote: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MorningNote()
    private static let onKey = "morningNote.on", hourKey = "morningNote.hour", minuteKey = "morningNote.minute"
    private static let prefix = "today-"

    private(set) var isOn = UserDefaults.standard.bool(forKey: MorningNote.onKey)
    var hour = UserDefaults.standard.object(forKey: MorningNote.hourKey) as? Int ?? 8 { didSet { save() } }
    var minute = UserDefaults.standard.object(forKey: MorningNote.minuteKey) as? Int ?? 30 { didSet { save() } }
    /// Shown under the switch when notifications are turned off for the app in Settings.
    private(set) var blocked = false
    @ObservationIgnored weak var library: JazzLibrary?

    private var center: UNUserNotificationCenter { .current() }

    /// Becomes the notification delegate (so tapping a note opens its page) and refreshes the schedule.
    func start(library: JazzLibrary) {
        self.library = library
        center.delegate = self
        Task { await reschedule() }
    }

    func setOn(_ on: Bool) async {
        if on {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            blocked = !granted
            isOn = granted
        } else {
            isOn = false
        }
        UserDefaults.standard.set(isOn, forKey: Self.onKey)
        await reschedule()
    }

    private func save() {
        UserDefaults.standard.set(hour, forKey: Self.hourKey)
        UserDefaults.standard.set(minute, forKey: Self.minuteKey)
        Task { await reschedule() }
    }

    /// Replaces the scheduled notes with the next seven days' (from today, if today's time is still ahead).
    func reschedule() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isOn, let library else { return }
        let settings = await center.notificationSettings()
        blocked = settings.authorizationStatus == .denied
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire > .now,
                  let c = library.todayWidget(on: cal.date(byAdding: .hour, value: 12, to: day) ?? day, calendar: cal)
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = c.label == "TODAY IN JAZZ" ? "Today in jazz" : c.label.capitalized
            content.body = c.line
            content.userInfo = ["link": c.link.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                                                        repeats: false)
            let id = Self.prefix + fire.formatted(.iso8601.year().month().day())
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    // The completion-handler forms, not the async ones: for the async forms the system calls its completion handler on
    // a background thread, and UIKit asserts it's on the main thread, so tapping a note crashed the app.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = (response.notification.request.content.userInfo["link"] as? String).flatMap(URL.init(string:))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let link { AppContext.shared.open(link) }
            }
            completionHandler()
        }
    }
}

/// The switch and time for the morning note, in both apps' Settings.
struct MorningNoteSettings: View {
    @Bindable var note = MorningNote.shared

    var body: some View {
        Section {
            Toggle("Morning note", isOn: Binding(get: { note.isOn }, set: { on in Task { await note.setOn(on) } }))
            if note.isOn {
                DatePicker("Time", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: note.hour, minute: note.minute, second: 0, of: .now) ?? .now },
                    set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        note.hour = c.hour ?? 8; note.minute = c.minute ?? 30
                    }), displayedComponents: .hourAndMinute)
            }
            if note.blocked {
                Text("Notifications are off for Jazz Discovery. Turn them on in System Settings ▸ Notifications.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Today in Jazz")
        } footer: {
            Text("Each morning, whose birthday it is in jazz or what was recorded on that date. Scheduled on this device; nothing is sent anywhere.")
        }
    }
}
