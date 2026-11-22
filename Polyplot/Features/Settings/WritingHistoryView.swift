import PolyplotCore
import SwiftUI
import UIKit

/// Settings → Writing history: every finished writing task in the language being learned, most recent
/// first, with its feedback and the learner's hours and level when it was written. Swipe one to delete it;
/// ⋯ → Clear all history deletes them all, after a second check. Kept in backups. See docs/03-experience.md "Settings".
struct WritingHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingClear = false
    @State private var showingDeletedNote = false

    var body: some View {
        let entries = model.writingHistory
        List {
            Group {
                if entries.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No writing yet", systemImage: "doc.text")
                        } description: {
                            Text(model.profile?.keepsWritingHistory == false
                                 ? "Keep writing history is off, so new writing isn't kept. Switch it on in Settings to keep each writing task with its feedback."
                                 : "Each writing task you finish is kept here with its feedback, newest first.")
                        }
                    }
                } else {
                    Section {
                        ForEach(entries) { entry in
                            WritingHistoryRow(entry: entry, standing: model.standing(when: entry))
                        }
                        .onDelete { offsets in
                            for index in offsets { model.deleteWriting(entries[index]) }
                            showingDeletedNote = true
                        }
                    } footer: {
                        Text("Swipe one to delete it. \(WritingHistoryNote.cards)")
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
            Text("Every piece of \(model.pack.name) writing and its feedback will be deleted. This can't be undone. \(WritingHistoryNote.cards)")
        }
        .deletedWritingNote(isShowing: $showingDeletedNote)
    }
}

/// One finished writing task: when, the hours and level then, the prompt, the text, and its feedback.
/// Also shown in a day's summary on the path (`DaySummarySheet`).
struct WritingHistoryRow: View {
    let entry: WritingEntry
    let standing: (hours: Double, band: Band, estimated: Bool)
    /// Which text was just copied, for a moment's "Copied".
    @State private var copied: String?

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
            HStack(alignment: .top, spacing: 8) {
                Text(entry.text)
                    .font(.rounded(.body, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                copyButton("writing", entry.text, label: "Copy your writing")
            }
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

    /// A copy icon that puts `text` on the clipboard and turns into a tick for a moment. Borderless, so in
    /// a list only the button reacts, not the whole row.
    private func copyButton(_ id: String, _ text: String, label: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(.snappy) { copied = id }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy) { if copied == id { copied = nil } }
            }
        } label: {
            Image(systemName: copied == id ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(copied == id ? Palette.leaf : Palette.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(copied == id ? "Copied" : label)
        .sensoryFeedback(.success, trigger: copied == id)
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
            section("How a native speaker might say it", feedback.naturalRewrite, Palette.sky, copy: "Copy the native version")
        }
        if !feedback.strengths.isEmpty {
            section("What went well", feedback.strengths.map { "• \($0)" }.joined(separator: "\n"), Palette.sun)
        }
        Text("Checked by \(feedback.engine)")
            .font(.rounded(.caption2, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
    }

    /// A titled block; with `copy`, a copy icon for its text beside the title.
    private func section(_ title: String, _ text: String, _ color: Color, copy: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let copy { copyButton(title, text, label: copy) }
            }
            Text(text)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum WritingHistoryNote {
    /// Deleting writing leaves the mistake cards made from it.
    static let cards = "Snippets of it may still appear in your mistake deck until you delete those cards."
}

extension View {
    /// After a piece of writing is swiped away: a note for a few seconds that its mistake cards stay.
    func deletedWritingNote(isShowing: Binding<Bool>) -> some View {
        overlay(alignment: .bottom) {
            if isShowing.wrappedValue {
                Label("Deleted. \(WritingHistoryNote.cards)", systemImage: "trash")
                    .font(.rounded(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card).shadow(radius: 6, y: 2))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.snappy) { isShowing.wrappedValue = false }
                    }
            }
        }
        .animation(.snappy, value: isShowing.wrappedValue)
    }
}
