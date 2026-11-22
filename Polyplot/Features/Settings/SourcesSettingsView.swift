import PolyplotCore
import SwiftUI

/// Settings → Sources: the language's built-in sources (tap one to see what it is, switch it on or off),
/// the learner's own (Custom sources), and where the learner is in each course. See docs/03-experience.md "Settings".
struct SourcesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var sourceInfo: SourceKind?

    var body: some View {
        Form {
            if let profile = model.profile {
                Group { sections(profile) }
                    .polyplotRows()
            }
        }
        .polyplotListBackground()
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sourceInfo) { SourceInfoSheet(source: $0) }
    }

    @ViewBuilder
    private func sections(_ profile: LearnerProfile) -> some View {
        if !profile.pack.roles.isEmpty {
            Section {
            ForEach(profile.pack.roles, id: \.self) { source in
                HStack {
                    // The name opens what the source is; the switch turns it on or off.
                    Button {
                        sourceInfo = source
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(SourceCopy.name(source)).foregroundStyle(Palette.ink)
                                Image(systemName: "info.circle")
                                    .font(.rounded(.caption, weight: .bold))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            // A source the learner's level leaves out for now: "Starts at A2.1".
                            if let note = profile.pack.levelNote(for: source, at: profile.band) {
                                Text(note)
                                    .font(.rounded(.caption, weight: .medium))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Toggle(SourceCopy.name(source), isOn: binding(
                        get: { profile.enabledSources.contains(source) },
                        set: { on in
                            var sources = profile.enabledSources
                            if on { sources.insert(source) } else { sources.remove(source) }
                            profile.enabledSources = sources
                        }
                    ))
                    .labelsHidden()
                }
            }
            } header: {
                Text("Built in")
            } footer: {
                Text("Tap a source to see what it is and where to find it.")
            }
        }
        Section {
            NavigationLink {
                CustomSourcesView()
            } label: {
                let custom = profile.customSources
                let on = custom.filter(\.isEnabled).count
                LabeledContent("Custom sources", value: custom.isEmpty ? "None" : on == custom.count ? "\(on)" : "\(on) of \(custom.count) on")
            }
        } header: {
            Text("Your own")
        } footer: {
            Text(profile.pack.isCustom
                 ? "Have at least one for listening, plus the built-in sources above."
                 : "A podcast, a textbook, another app: anything else you learn with.")
        }
        // Where the learner is in each course, in that source's own terms (none for an "Other language").
        if profile.pack.graded != nil || profile.pack.course != nil || profile.pack.drill != nil || profile.pack.series != nil {
            Section {
            let pack = profile.pack
            if let graded = pack.graded {
                // A window (e.g. 40–45) that slides by 1 per tap.
                Stepper("\(SourceCopy.name(.gradedVideo)): \(profile.dsDifficultyLow)–\(profile.dsDifficultyHigh)", value: binding(
                    get: { profile.dsDifficultyLow },
                    set: { low in
                        let low = max(graded.scale.lowerBound, low)
                        profile.dsDifficulty = low...(low + graded.windowWidth)
                    }
                ), in: graded.scale.lowerBound...(graded.scale.upperBound - graded.windowWidth))
            }
            if let course = pack.course {
                // The last track finished, like the series' "seen": finishing 13 means you're up to 14.
                Stepper(profile.languageTransferLastTrack == 0
                        ? "\(SourceCopy.name(.audioCourse)): not started"
                        : "\(SourceCopy.name(.audioCourse)): finished Track \(profile.languageTransferLastTrack)", value: binding(
                    get: { profile.languageTransferLastTrack },
                    set: { profile.languageTransferLastTrack = $0; profile.languageTransferRepeatPending = false }
                ), in: 0...course.tracks)
            }
            if let drill = pack.drill {
                // Section and unit as two full steppers in one row, so they read as one entry.
                VStack(alignment: .leading, spacing: 16) {
                    Text(SourceCopy.name(.drillApp))
                    Stepper(value: binding(get: { profile.duolingoSection }, set: { profile.duolingoSection = $0 }), in: drill.sections) {
                        Text("Section \(profile.duolingoSection)").foregroundStyle(Palette.secondaryText)
                    }
                    Stepper(value: binding(get: { profile.duolingoUnit }, set: { profile.duolingoUnit = $0 }), in: drill.units) {
                        Text("Unit \(profile.duolingoUnit)").foregroundStyle(Palette.secondaryText)
                    }
                }
                .padding(.vertical, 2)
            }
            if let series = pack.series {
                // One step = one part (an episode is watched in parts at the early levels), so a half-watched episode can be set.
                Stepper(seriesProgressLabel(profile, series), value: binding(
                    get: { profile.extraEpisodesWatched * series.intensiveParts + profile.extraPartsDoneInEpisode },
                    set: { parts in
                        profile.extraEpisodesWatched = parts / series.intensiveParts
                        profile.extraPartsDoneInEpisode = parts % series.intensiveParts
                    }
                ), in: 0...(series.episodes * series.intensiveParts))
            }
            if let drill = pack.drill, profile.band == drill.optionalBand {
                Toggle("Keep a \(SourceCopy.name(.drillApp)) warm-up", isOn: binding(get: { profile.keepDuolingoInB2 }, set: { profile.keepDuolingoInB2 = $0 }))
            }
            } header: {
                Text("Where you are")
            } footer: {
                Text("Polyplot moves these on as you log tasks. Fix them here if they're out.")
            }
        }
    }

    /// The last part seen: "Extra en Español: seen Ep 3 Part 2" (or "not started").
    private func seriesProgressLabel(_ profile: LearnerProfile, _ series: LearnerSeries) -> String {
        let name = SourceCopy.name(.learnerSeries)
        let parts = profile.extraEpisodesWatched * series.intensiveParts + profile.extraPartsDoneInEpisode
        guard parts > 0 else { return "\(name): not started" }
        let episode = (parts - 1) / series.intensiveParts + 1
        let part = (parts - 1) % series.intensiveParts + 1
        return "\(name): seen Ep \(episode) Part \(part)"
    }

    /// A binding that saves through the app model, so every change persists and refreshes views.
    private func binding<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: { value in
            set(value)
            model.save()
        })
    }
}
