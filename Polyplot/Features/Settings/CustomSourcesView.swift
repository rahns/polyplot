import PolyplotCore
import SwiftUI

/// Settings → Sources → Custom sources: the learner's own sources (a podcast, a textbook, another app), each
/// with a study type and a task length range. Each can be switched off, edited (tap) or deleted (swipe).
/// The planner shares each strand between these and the built-in tasks. See docs/03-experience.md "Settings".
struct CustomSourcesView: View {
    @Environment(AppModel.self) private var model
    /// The source being edited, or a new one being added.
    @State private var editing: CustomSource?
    @State private var isNew = false

    var body: some View {
        let sources = model.profile?.customSources ?? []
        Form {
            Group {
                if sources.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No custom sources yet", systemImage: "square.stack.3d.up")
                        } description: {
                            Text("Add a podcast, a textbook, another app or anything else you learn with. Tap + to add one.")
                        }
                    }
                } else {
                    Section {
                        ForEach(sources) { source in
                            row(source)
                        }
                        .onDelete { offsets in
                            var updated = sources
                            updated.remove(atOffsets: offsets)
                            model.setCustomSources(updated)
                        }
                    } footer: {
                        Text("These sources are included in your plans.")
                    }
                }
            }
            .polyplotRows()
        }
        .polyplotListBackground()
        .navigationTitle("Custom sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Add", systemImage: "plus") {
                isNew = true
                editing = CustomSource(name: "", strand: .input, minMinutes: 10, maxMinutes: 20)
            }
        }
        .sheet(item: $editing) { source in
            CustomSourceEditor(source: source, isNew: isNew) { saved in
                var updated = model.profile?.customSources ?? []
                if let index = updated.firstIndex(where: { $0.id == saved.id }) {
                    updated[index] = saved
                } else {
                    updated.append(saved)
                }
                model.setCustomSources(updated)
            }
        }
    }

    private func row(_ source: CustomSource) -> some View {
        HStack(spacing: 12) {
            Button {
                isNew = false
                editing = source
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: TaskCopy.symbol(for: source.kind))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(source.kind.color))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .foregroundStyle(Palette.ink)
                        Text("\(TaskCopy.otherName(source.strand)) · \(Self.rangeText(source.minuteRange))")
                            .font(.rounded(.caption, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .opacity(source.isEnabled ? 1 : 0.5)
            }
            .buttonStyle(.borderless)
            Spacer()
            Toggle(source.name, isOn: Binding(
                get: { source.isEnabled },
                set: { on in
                    var updated = model.profile?.customSources ?? []
                    guard let index = updated.firstIndex(where: { $0.id == source.id }) else { return }
                    updated[index].isEnabled = on
                    model.setCustomSources(updated)
                }
            ))
            .labelsHidden()
        }
    }

    static func rangeText(_ range: MinuteRange) -> String {
        range.min == range.max ? "\(range.min) min" : "\(range.min)–\(range.max) min"
    }
}

/// Adding or editing one custom source: its name, study type and how long its tasks can be.
/// Also used by "Other language" setup in onboarding.
struct CustomSourceEditor: View {
    @State private var source: CustomSource
    let isNew: Bool
    let onSave: (CustomSource) -> Void

    init(source: CustomSource, isNew: Bool, onSave: @escaping (CustomSource) -> Void) {
        _source = State(initialValue: source)
        self.isNew = isNew
        self.onSave = onSave
    }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { source.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Name") {
                        TextField("e.g. My favourite podcast", text: $source.name)
                            .textInputAutocapitalization(.words)
                    }
                    Section {
                        Picker("Study type", selection: $source.strand) {
                            ForEach([Strand.input, .languageFocused, .output, .fluency], id: \.self) { strand in
                                Text(TaskCopy.otherName(strand)).tag(strand)
                            }
                        }
                    } footer: {
                        Text(strandNote)
                    }
                    Section {
                        Stepper("Shortest: \(source.minMinutes) min") {
                            source.minMinutes = Self.longer(source.minMinutes)
                            source.maxMinutes = max(source.maxMinutes, source.minMinutes)
                        } onDecrement: {
                            source.minMinutes = Self.shorter(source.minMinutes)
                        }
                        Stepper("Longest: \(source.maxMinutes) min") {
                            source.maxMinutes = Self.longer(source.maxMinutes)
                        } onDecrement: {
                            source.maxMinutes = Self.shorter(source.maxMinutes)
                            source.minMinutes = min(source.minMinutes, source.maxMinutes)
                        }
                    } header: {
                        Text("Task length")
                    } footer: {
                        Text("Polyplot plans it for somewhere in this range, depending on how much time you have that day.")
                    }
                }
                .polyplotRows()
            }
            .polyplotListBackground()
            .navigationTitle(isNew ? "Add a source" : "Edit source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        source.name = trimmedName
                        onSave(source)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    /// 1-minute steps up to 10 minutes, 5-minute steps after, within `CustomSource.minuteLimits`.
    private static func longer(_ minutes: Int) -> Int { min(minutes < 10 ? minutes + 1 : minutes + 5, CustomSource.minuteLimits.upperBound) }
    private static func shorter(_ minutes: Int) -> Int { max(minutes <= 10 ? minutes - 1 : minutes - 5, CustomSource.minuteLimits.lowerBound) }

    /// What the study type means, and a warning when today's plan gives that type no time at all.
    private var strandNote: String {
        let what = source.strand.ownSourceExpectation
        guard let profile = model.profile, (model.snapshot(for: profile).strandTargets[source.strand] ?? 0) == 0 else { return what }
        return what + " Your plan has no \(TaskCopy.otherName(source.strand).lowercased()) at the moment, so it won't be planned until it does."
    }
}
