import PolyplotCore
import SwiftUI

/// Settings → Writing history: every finished writing task in the language being learned, most recent
/// first, with its feedback and the learner's hours and level when it was written. Swipe one to delete it;
/// ⋯ → Clear all history deletes them all, after a second check. Kept in backups. See docs/03-experience.md "Settings".
struct WritingHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingClear = false

    var body: some View {
        let entries = model.writingHistory
        List {
            Group {
                if entries.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No writing yet", systemImage: "doc.text")
                        } description: {
                            Text("Each writing task you finish is kept here with its feedback, newest first.")
                        }
                    }
                } else {
                    Section {
                        ForEach(entries) { entry in
                            WritingHistoryRow(entry: entry, standing: model.standing(when: entry))
                        }
                        .onDelete { offsets in
                            for index in offsets { model.deleteWriting(entries[index]) }
                        }
                    } footer: {
                        Text("Swipe one to delete it. Mistake cards made from it stay in the deck.")
                    }
                }
            }
            .polyplotRows()
        }
        .polyplotListBackground()
        .navigationTitle("Writing history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Clear all history", systemImage: "trash", role: .destructive) { confirmingClear = true }
                    .disabled(entries.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        .confirmationDialog("Clear all writing history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear \(entries.count) \(entries.count == 1 ? "piece" : "pieces") of writing", role: .destructive) {
                withAnimation { model.clearWritingHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every piece of \(model.pack.name) writing and its feedback will be deleted. This can't be undone. Mistake cards made from them stay.")
        }
    }
}

/// One finished writing task: when, the hours and level then, the prompt, the text, and its feedback.
/// Also shown in a day's summary on the path (`DaySummarySheet`).
struct WritingHistoryRow: View {
    let entry: WritingEntry
    let standing: (hours: Double, band: Band, estimated: Bool)

    private var feedback: CorrectionService.Result? {
        entry.feedbackJSON.flatMap { try? JSONDecoder().decode(CorrectionService.Result.self, from: $0) }
    }

    private var kind: TaskKind { TaskKind(rawValue: entry.taskRaw) ?? .writeGuided }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: TaskCopy.symbol(for: kind))
                        .foregroundStyle(kind.color)
                    Text(TaskCopy.title(for: kind))
                        .font(.rounded(.headline, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
                Text(standingText)
                    .font(.rounded(.caption, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
            }
            if !entry.prompt.isEmpty {
                Text(entry.prompt)
                    .font(.rounded(.subheadline, weight: .medium))
                    .italic()
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(entry.text)
                .font(.rounded(.body, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let feedback {
                feedbackView(feedback)
            } else {
                Label("Not checked", systemImage: "minus.circle")
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            if !entry.rewrite.isEmpty {
                section("Your rewrite", entry.rewrite, Palette.leaf)
            }
        }
        .padding(.vertical, 6)
    }

    /// "42.5 training hours · A2.1 Explorer"; "≈" when it was worked out afterwards.
    private var standingText: String {
        let hours = standing.hours < 100 ? String(format: "%.1f", standing.hours) : "\(Int(standing.hours.rounded()))"
        let level = "\(standing.band.rawValue) \(ActiveLanguage.levelName(standing.band))"
        return "\(standing.estimated ? "≈ " : "")\(hours) training hours · \(standing.estimated ? "≈ " : "")\(level)"
    }

    @ViewBuilder
    private func feedbackView(_ feedback: CorrectionService.Result) -> some View {
        if let notice = feedback.notice {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .font(.rounded(.caption, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if feedback.corrections.isEmpty {
            Label("No mistakes found", systemImage: "checkmark.seal.fill")
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(Palette.leaf)
        } else {
            ForEach(Array(feedback.corrections.enumerated()), id: \.offset) { _, correction in
                CorrectionRow(correction: correction)
            }
        }
        if !feedback.naturalRewrite.isEmpty {
            section("How a native speaker might say it", feedback.naturalRewrite, Palette.sky)
        }
        if !feedback.strengths.isEmpty {
            section("What went well", feedback.strengths.map { "• \($0)" }.joined(separator: "\n"), Palette.sun)
        }
        Text("Checked by \(feedback.engine)")
            .font(.rounded(.caption2, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
    }

    private func section(_ title: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.rounded(.subheadline, weight: .heavy))
                .foregroundStyle(color)
            Text(text)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
