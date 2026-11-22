import PolyplotCore
import SwiftUI

/// Settings → Level & training hours: change the level or the training hours by hand, after setup.
/// Three steps, since it reshapes every plan from now on: pick the new values (with a nudge to save a
/// backup first), review exactly what changes and tick that a backup is saved or not needed, then a final
/// "Are you sure?" that offers the backup once more. See docs/03-experience.md "Settings".
struct LevelSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var band: Band = .a2_1
    @State private var hours = 0
    @State private var loaded = false
    @State private var reviewing = false
    @State private var confirmingFinal = false
    @State private var backupDocument: BackupDocument?
    @State private var exporting = false
    @State private var message: String?

    var body: some View {
        Form {
            if let profile = model.profile {
                Group { sections(profile) }
                    .polyplotRows()
            }
        }
        .polyplotListBackground()
        .navigationTitle("Level & training hours")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let profile = model.profile else { return }
            band = profile.band
            hours = Int(model.trainingHours.rounded())
            loaded = true
        }
        .sheet(isPresented: $reviewing) {
            if let profile = model.profile {
                LevelChangeReview(profile: profile, band: band, hours: Double(hours)) {
                    reviewing = false
                    // Once the sheet has gone, the last check.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmingFinal = true }
                } onBackup: {
                    reviewing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { saveBackup() }
                }
            }
        }
        .alert("Are you sure?", isPresented: $confirmingFinal) {
            Button("Save a backup first") { saveBackup() }
            Button("Change it", role: .destructive) {
                model.changeStanding(band: band, trainingHours: Double(hours))
                message = "Done. You're at \(band.rawValue) with \(hours) training hours."
            }
            Button("Keep things as they are", role: .cancel) {}
        } message: {
            Text("Every plan from now on follows the new level and hours. Your history stays, but this can't be undone automatically: to go back, set them again or restore a backup.")
        }
        .fileExporter(isPresented: $exporting, document: backupDocument, contentType: .polyplotBackup, defaultFilename: BackupDocument.defaultFilename()) { result in
            switch result {
            case .success(let url): message = "Saved \(url.lastPathComponent). You can make the change now."
            case .failure(let error): message = "Couldn't save the backup: \(error.localizedDescription)"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func sections(_ profile: LearnerProfile) -> some View {
        let pack = profile.pack
        let logged = model.loggedHours
        let minimum = Int(logged.rounded(.down))
        Section {
            LabeledContent("Level", value: "\(profile.band.rawValue) \(pack.levelName(profile.band))")
            LabeledContent("Training hours", value: "\(Int(model.trainingHours.rounded())) h")
        } header: {
            Text("Now")
        } footer: {
            Text("\(Int(logged.rounded())) h logged in Polyplot, plus \(Int(Band.trainingHours(fromListening: profile.baselineInputHours).rounded())) h from before (\(Int(profile.baselineInputHours.rounded())) h of listening).")
        }
        Section {
            Label("Changing these reshapes every plan from now on. Save a backup first, so you can put everything back if it doesn't feel right.", systemImage: "exclamationmark.shield.fill")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Button("Save a backup", systemImage: "square.and.arrow.down") { saveBackup() }
        }
        Section {
            Picker("Level", selection: $band) {
                ForEach(Band.allCases, id: \.self) { level in
                    Text("\(level.rawValue) \(pack.levelName(level))").tag(level)
                }
            }
        } header: {
            Text("New level")
        } footer: {
            Text("Sets each day's balance between listening, grammar & vocab, speaking & writing and fluency, the weekly targets and which sources are planned. Normally it moves up through the level-up check.")
        }
        Section {
            NumberStepper(title: "Training hours", value: $hours, range: minimum...max(5000, minimum), step: 10)
        } header: {
            Text("New training hours")
        } footer: {
            let pointsTo = pack.levels.band(forHours: Double(hours))
            Text("Every minute of practice counts, plus listening from before Polyplot. Your \(minimum) h logged here can't be taken away, so it's the lowest it can go. \(hours) h is where \(pointsTo.rawValue) usually is"
                 + (pointsTo == band ? "." : "; you've picked \(band.rawValue)."))
        }
        Section {
            Button("Review the change") { reviewing = true }
                .disabled(band == profile.band && hours == Int(model.trainingHours.rounded()))
        } footer: {
            Text("Nothing changes until you've reviewed it and confirmed.")
        }
    }

    private func saveBackup() {
        do {
            backupDocument = try model.makeBackup()
            exporting = true
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Step 2: exactly what changes and what doesn't, and a tick that a backup is saved (or not needed).
private struct LevelChangeReview: View {
    let profile: LearnerProfile
    let band: Band
    let hours: Double
    let onContinue: () -> Void
    let onBackup: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var backupAcknowledged = false

    var body: some View {
        let pack = profile.pack
        let hoursNow = model.trainingHours
        let levelChanges = band != profile.band
        let hoursChange = Int(hours.rounded()) != Int(hoursNow.rounded())
        let newDate = GoalPace.arrival(atHours: profile.goalHours, currentHours: hours, weeklyMinutes: profile.weeklyGoalMinutes, from: .now)
        NavigationStack {
            Form {
                Group {
                    Section("What changes") {
                        if levelChanges {
                            change("Level", "\(profile.band.rawValue) \(pack.levelName(profile.band))", "\(band.rawValue) \(pack.levelName(band))")
                        }
                        if hoursChange {
                            change("Training hours", "\(Int(hoursNow.rounded())) h", "\(Int(hours.rounded())) h")
                        }
                        if let date = profile.targetDate, hoursChange,
                           !Calendar.current.isDate(date, equalTo: newDate, toGranularity: .month) {
                            change("\(profile.goal) by", date.formatted(.dateTime.month(.abbreviated).year()), newDate.formatted(.dateTime.month(.abbreviated).year()))
                        }
                    }
                    Section("What this means") {
                        if levelChanges {
                            point("calendar", "From today's plan (if you haven't started it) or tomorrow's, plans follow \(band.rawValue): its balance between listening, grammar & vocab, speaking & writing and fluency, its weekly targets, and the sources used at that level."
                                  + (profile.strandBalance != nil ? " Your custom plan balance stays as it is." : ""))
                            if let next = band.next {
                                point("arrow.up.circle", "The level-up check for \(next.rawValue) opens at \(Int(pack.levels.threshold(next))) training hours.")
                            }
                        }
                        if hoursChange {
                            point("clock", "Your \(Int(model.loggedHours.rounded())) h of logged practice stay. Only the hours from before Polyplot change, so Progress, projections and your goal date use the new total. Your weekly goal stays at \(profile.weeklyGoalMinutes) min.")
                            if hours > hoursNow {
                                point("waveform", "More listening hours can unlock voice notes and calls sooner.")
                            } else {
                                point("waveform", "Speaking stages already unlocked stay unlocked.")
                            }
                        }
                        point("checkmark.shield", "Your history, streak, path, mistake deck and writing don't change.")
                    }
                    Section {
                        Toggle("I've saved a backup, or don't need one", isOn: $backupAcknowledged)
                        Button("Save a backup now", systemImage: "square.and.arrow.down") { onBackup() }
                    } footer: {
                        Text("A backup is the only way to put everything back exactly as it was.")
                    }
                }
                .polyplotRows()
            }
            .polyplotListBackground()
            .navigationTitle("Review the change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { onContinue() }
                        .disabled(!backupAcknowledged)
                }
            }
        }
    }

    private func change(_ title: String, _ before: String, _ after: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.rounded(.caption, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
            HStack(spacing: 8) {
                Text(before).foregroundStyle(Palette.secondaryText)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Palette.secondaryText)
                Text(after).foregroundStyle(Palette.ink)
            }
            .font(.rounded(.body, weight: .bold))
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.rounded(.subheadline, weight: .medium))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
