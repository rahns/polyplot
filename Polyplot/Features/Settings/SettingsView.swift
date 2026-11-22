import PolyplotCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    /// The second, final check before a language's progress is deleted.
    @State private var confirmingDeleteForGood = false
    @State private var backupDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var message: String?
    /// "Gemini, then Groq", "Groq" or "Not set up".
    @State private var checkers = SettingsView.checkersText()

    var body: some View {
        NavigationStack {
            Form {
                if let profile = model.profile {
                    Group { sections(profile) }
                        .polyplotRows()
                }
            }
            .polyplotListBackground()
            .navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: backupDocument, contentType: .polyplotBackup, defaultFilename: BackupDocument.defaultFilename()) { result in
                switch result {
                case .success(let url): message = "Saved \(url.lastPathComponent)."
                case .failure(let error): message = "Couldn't save the backup: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $importing) {
                BackupImportPicker { result in
                    importing = false
                    switch result {
                    case .success(let data): pendingRestore = data
                    case .failure(let error): message = "Couldn't read that file: \(error.localizedDescription)"
                    case nil: break
                    }
                }
                .ignoresSafeArea()
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func sections(_ profile: LearnerProfile) -> some View {
        // Which language is being learned: first, above everything that belongs to it.
        Section {
            // Each language has its own level, plan, goal and streak. One without a profile yet starts its setup;
            // "Other language…" sets up a language Polyplot has no sources for, from the learner's own.
            Picker("Learning", selection: Binding(get: { model.languageCode }, set: { code in
                model.setLanguage(code == Self.newCustomLanguageTag ? LanguagePack.newCustomCode() : code, announce: true)
            })) {
                ForEach(LanguagePack.all) { pack in
                    Text(pack.name).tag(pack.code)
                }
                ForEach(model.profiles.filter { LanguagePack.isCustom($0.languageCode) }, id: \.languageCode) { custom in
                    Text("\(custom.pack.flag) \(custom.pack.name)").tag(custom.languageCode)
                }
                Text("Other language…").tag(Self.newCustomLanguageTag)
            }
            if profile.pack.isCustom {
                TextField("Name", text: Binding(get: { profile.customLanguageName }, set: { model.renameCustomLanguage(name: $0) }))
                    .textInputAutocapitalization(.words)
                NavigationLink {
                    Form {
                        Section {
                            EmojiPicker(selection: Binding(get: { profile.pack.flag }, set: { model.renameCustomLanguage(flag: $0) }))
                                .padding(.vertical, 6)
                        }
                        .polyplotRows()
                    }
                    .polyplotListBackground()
                    .navigationTitle("Emoji")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    LabeledContent("Emoji", value: profile.pack.flag)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Each language keeps its own level, plan, goal and streak. For a language Polyplot doesn't have, choose Other language…")
        }
        // The language being learned: what each day's plan is built from.
        Section {
            NavigationLink {
                GoalSettingsView()
            } label: {
                LabeledContent("Goal", value: profile.targetDate.map { "\(profile.goal) by \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? profile.goal)
            }
            NavigationLink {
                SourcesSettingsView()
            } label: {
                LabeledContent("Sources", value: sourcesSummary(profile))
            }
            NavigationLink {
                LessonSettingsView()
            } label: {
                LabeledContent("Classes/Tutoring", value: profile.lessonSchedule.summary(weekStartsOnSunday: profile.weekStartsOnSunday))
            }
            NavigationLink {
                PlanBalanceView()
            } label: {
                HStack(spacing: 10) {
                    Text("Plan balance")
                    Spacer()
                    if let balance = profile.strandBalance {
                        // A custom split at a glance, each share in its strand's colour.
                        HStack(spacing: 6) {
                            ForEach([Strand.input, .languageFocused, .output, .fluency], id: \.self) { strand in
                                Text("\(balance[strand])")
                                    .font(.rounded(.subheadline, weight: .black))
                                    .foregroundStyle(strand.color)
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Text("For your level").foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        } header: {
            GroupHeading(title: "\(profile.pack.name) \(profile.pack.flag)", section: "Your plan")
        } footer: {
            Text("\(profile.weeklyGoalMinutes) min a week. Each language has its own goal, sources and plan.")
        }
        Section {
            Toggle(isOn: Binding(get: { profile.travelMode }, set: { model.setTravelMode($0) })) {
                subtitled("Travel mode", "A real-world \(profile.pack.name) mission every day"
                          + (model.canChangeBudget ? "" : ", from tomorrow"))
            }
            if profile.pack.has(.drillApp) {
                Toggle(isOn: binding(get: { profile.alwaysIncludeDuolingo }, set: { profile.alwaysIncludeDuolingo = $0; model.replanTodayIfNotStarted() })) {
                    subtitled("Always include \(SourceCopy.name(.drillApp))", "If you're keeping a streak going")
                }
            }
            // Speaking stages pace the exchange partner, which an "Other language" doesn't have.
            if profile.pack.has(.exchange) {
                Toggle("Ready for voice notes", isOn: binding(
                    get: { profile.speakingStage >= .voiceNotes },
                    set: { model.setSpeakingStage(.voiceNotes, on: $0) }
                ))
                Toggle("Ready for live calls", isOn: binding(
                    get: { profile.speakingStage >= .calls },
                    set: { model.setSpeakingStage(.calls, on: $0) }
                ))
                .disabled(profile.speakingStage < .voiceNotes)
            }
        } header: {
            Text("Plan options")
        } footer: {
            if profile.pack.has(.exchange) {
                Text("Voice notes and calls switch on by themselves as you progress; switch one on early if you feel ready. Switched off, it stays off.")
            }
        }
        Section {
            Toggle("Daily reminder", isOn: binding(
                get: { profile.reminderEnabled },
                set: { on in
                    profile.reminderEnabled = on
                    Task {
                        if on { _ = await Reminders.requestPermission() }
                        model.refreshReminders()
                    }
                }
            ))
            if profile.reminderEnabled {
                DatePicker("Time", selection: binding(
                    get: { Calendar.current.date(from: DateComponents(hour: profile.reminderHour, minute: profile.reminderMinute)) ?? .now },
                    set: { date in
                        profile.reminderHour = Calendar.current.component(.hour, from: date)
                        profile.reminderMinute = Calendar.current.component(.minute, from: date)
                        model.refreshReminders()
                    }
                ), displayedComponents: .hourAndMinute)
            }
            Picker("Week starts on", selection: Binding(
                get: { profile.weekStartsOnSunday },
                set: { model.setWeekStartsOnSunday($0) }
            )) {
                Text("Monday").tag(false)
                Text("Sunday").tag(true)
            }
            Button("Send a test notification", systemImage: "bell.badge") {
                Task {
                    let allowed = await Reminders.sendTest()
                    message = allowed
                        ? "A test notification arrives in 5 seconds. It shows even with Polyplot open."
                        : "Notifications are off for Polyplot. Turn them on in the iPhone's Settings → Notifications → Polyplot."
                }
            }
        } header: {
            Text("Reminders & week")
        } footer: {
            Text("Your weekly goal resets on the day your week starts.")
        }
        Section {
            NavigationLink {
                GeminiSettingsView { _ in checkers = SettingsView.checkersText() }
            } label: {
                LabeledContent("Writing feedback", value: checkers)
            }
            Toggle(isOn: Binding(get: { profile.keepsWritingHistory }, set: { model.setKeepsWritingHistory($0) })) {
                subtitled("Keep writing history", "Writing snippets can still appear in the mistake deck when this is off")
            }
            // The page is always there, so what's already kept can be read, copied or cleared with the toggle off.
            NavigationLink {
                WritingHistoryView()
            } label: {
                let count = model.writingHistory.count
                LabeledContent("Writing history", value: count == 0 ? "None yet" : "\(count)")
            }
        } header: {
            Text("Writing")
        } footer: {
            Text("Poly checks writing with your own free Gemini or GroqCloud key, shared by all your languages"
                 + (profile.pack.isCustom ? ". \(profile.pack.name) needs one: the basic checker doesn't know it." : "; without one, a basic checker is used."))
        }
        Section {
            // With another language set up, starting over deletes this one and switches back to that one.
            let current = profile.pack.name
            let fallback = model.profiles.first { $0.languageCode != profile.languageCode }?.pack.name
            Button(fallback.map { "Delete \(current) progress and switch back to \($0)" } ?? "Start over", role: .destructive) {
                confirmingReset = true
            }
            .confirmationDialog(fallback == nil ? "Start over?" : "Delete \(current) progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button(fallback.map { "Delete \(current) and switch to \($0)" } ?? "Delete everything and start again", role: .destructive) {
                    // Once the sheet has gone, one last check that says exactly what will be lost.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmingDeleteForGood = true }
                }
            } message: {
                // The leading line break gives the message a little room under the title.
                Text("\n" + (fallback.map { "Your \(current) streak, hours and history will be deleted. Your \($0) progress stays as it is." }
                     ?? "Your streak, hours and history for \(current) will be deleted. You'll go through onboarding again."))
            }
            .alert("Are you sure?", isPresented: $confirmingDeleteForGood) {
                Button("Save a backup first") { saveBackup() }
                Button("Delete \(current) for good", role: .destructive) { model.reset() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text(lossSummary(profile) + " This can't be undone. Save a backup first so you can bring it all back later.")
            }
        }
        // Settings shared by every language.
        Section {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
        } header: {
            GroupHeading(title: "All languages", section: "Appearance")
        } footer: {
            Text("System follows your phone's light or dark mode.")
        }
        Section {
            Button("Save backup", systemImage: "square.and.arrow.down") { saveBackup() }
            Button("Restore from a backup", systemImage: "arrow.counterclockwise") { importing = true }
            .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
                Button("Replace my data with the backup", role: .destructive) {
                    guard let data = pendingRestore else { return }
                    pendingRestore = nil
                    do {
                        try model.restore(from: data)
                        checkers = SettingsView.checkersText()
                        message = "Backup restored."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            } message: {
                Text("Everything in Polyplot now will be replaced by what's in the file.")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("One file with every language, to keep in iCloud Drive. Restoring replaces everything in Polyplot with the file's contents.")
        }
        Section {
            ShareLink(item: URL(string: "https://github.com/rahns/polyplot/releases/latest")!,
                      subject: Text("Polyplot"),
                      message: Text("I'm using Polyplot to plan my \(profile.pack.name). Download it here (you sign it with your own certificate):")) {
                Label("Share Polyplot with a friend", systemImage: "square.and.arrow.up")
            }
            Link(destination: Self.feedbackEmail) {
                Label("Report a bug or suggest something", systemImage: "envelope")
            }
            NavigationLink("Credits") { CreditsView() }
            // Changing the level or hours by hand, and troubleshooting, behind a warning.
            NavigationLink("Advanced") { AdvancedSettingsView() }
        } header: {
            Text("Help & about")
        } footer: {
            VStack(spacing: 4) {
                Text("Polyplot \(DiagnosticsModel.appVersion)")
                Text("Made out of necessity (and with ❤️) by Rahn")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            // A little room between the credit and the tab bar.
            .padding(.bottom, 24)
        }
    }

    /// The language picker's "Other language…" entry: picking it sets up a new language with its own code.
    static let newCustomLanguageTag = "x-new"

    /// A new email to Rahn in the Mail app, with the app and iOS version filled in for bug reports.
    static var feedbackEmail: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "contact@rahnstavar.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Polyplot feedback"),
            URLQueryItem(name: "body", value: "\n\n\n— Polyplot \(DiagnosticsModel.appVersion) · iOS \(UIDevice.current.systemVersion)"),
        ]
        return components.url ?? URL(string: "mailto:contact@rahnstavar.com")!
    }

    static func checkersText() -> String { WritingCheckers.summary }

    private func saveBackup() {
        do {
            backupDocument = try model.makeBackup()
            exporting = true
        } catch {
            message = error.localizedDescription
        }
    }

    /// What deleting the language being learned loses: "You'll lose your 12-day streak, 34 hours over
    /// 41 days of French, your A2.2 level and 18 mistake cards."
    private func lossSummary(_ profile: LearnerProfile) -> String {
        let logs = model.logs
        let days = Set(logs.map { model.calendar.startOfDay(for: $0.date) }).count
        let hours = Int((Double(logs.reduce(0) { $0 + $1.minutes }) / 60).rounded())
        let streak = model.streak.streak
        let cards = model.allCards.count
        var parts: [String] = []
        if streak > 0 { parts.append("your \(streak)-day streak") }
        if days > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours") logged over \(days) \(days == 1 ? "day" : "days")") }
        parts.append(days > 0 ? "your \(profile.band.rawValue) level and plan history" : "your setup and \(profile.band.rawValue) level")
        if cards > 0 { parts.append("\(cards) mistake \(cards == 1 ? "card" : "cards")") }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts[0]
        return "You'll lose all your \(profile.pack.name) progress: \(list)."
    }

    /// The Sources row: "5 on · 2 custom".
    private func sourcesSummary(_ profile: LearnerProfile) -> String {
        let on = profile.pack.roles.filter(profile.enabledSources.contains).count
        let custom = profile.customSources.filter(\.isEnabled).count
        return [on > 0 ? "\(on) on" : nil, custom > 0 ? "\(custom) custom" : nil].compactMap { $0 }.joined(separator: " · ").ifEmpty("None")
    }

    /// A setting's name with a short line under it.
    private func subtitled(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.rounded(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
        }
    }

    /// A binding that saves through the app model, so every change persists and refreshes views.
    private func binding<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: { value in
            set(value)
            model.save()
        })
    }
}

/// The first section of a group carries the group's heading above its own: "Spanish 🇪🇸" over "Your plan".
/// Sharing one header keeps the gap between them small.
struct GroupHeading: View {
    let title: String
    let section: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.rounded(.title3, weight: .black))
                .foregroundStyle(Palette.ink)
                .textCase(nil)
            Text(section)
        }
    }
}


private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
