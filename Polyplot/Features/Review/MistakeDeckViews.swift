import PolyplotCore
import SwiftUI

/// Reviews due mistake cards one at a time: front → "Show answer" → Again / Good / Easy (FSRS, R7).
/// Only the card is drawn here; its buttons are `ReviewControls`, pinned below the scrolling content
/// so they're always in reach, however long the card.
struct ReviewDeckView: View {
    @Environment(AppModel.self) private var model
    let revealed: Bool
    let reviewed: Int

    var body: some View {
        let due = model.dueCards
        VStack(spacing: 18) {
            if let card = due.first {
                Text("\(due.count) due · \(reviewed) reviewed")
                    .font(.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(Palette.secondaryText)
                    .contentTransition(.numericText())
                CardFace(card: card, revealed: revealed)
                    .id(card.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                PolyView(mood: .cheering, size: 110, celebrate: reviewed)
                Text(reviewed == 0 ? "Nothing due right now" : "All caught up!")
                    .font(.rounded(.title3, weight: .black))
                    .foregroundStyle(Palette.ink)
                Text(reviewed == 0 ? "Cards come back just before you'd forget them." : "\(reviewed) cards reviewed. They'll come back just before you'd forget them.")
                    .font(.rounded(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: due.first?.id)
    }
}

/// "Show answer", then Again / Good / Easy, for the first due card. Empty once nothing is due.
/// Reviewing resumes a paused task timer.
struct ReviewControls: View {
    @Environment(AppModel.self) private var model
    @Binding var revealed: Bool
    @Binding var reviewed: Int

    var body: some View {
        if let card = model.dueCards.first {
            Group {
                if revealed {
                    HStack(spacing: 10) {
                        rateButton("Again", .again, Palette.coral, card)
                        rateButton("Good", .good, Palette.leaf, card)
                        rateButton("Easy", .easy, Palette.sky, card)
                    }
                } else {
                    Button("Show answer") {
                        model.resumeReviewIfPaused()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { revealed = true }
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Palette.sky))
                }
            }
            .transition(.opacity)
        }
    }

    private func rateButton(_ title: String, _ rating: FSRS.Rating, _ color: Color, _ card: ReviewCard) -> some View {
        Button(title) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                model.review(card, rating: rating)
                reviewed += 1
                revealed = false
            }
        }
        .buttonStyle(ChunkyButtonStyle(color: color))
    }
}

/// Reviewing outside a task (Progress → Mistake deck → Review): the card scrolls, its buttons stay put.
struct StandaloneReviewView: View {
    @State private var revealed = false
    @State private var reviewed = 0

    var body: some View {
        ScrollView {
            ReviewDeckView(revealed: revealed, reviewed: reviewed).padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            ReviewControls(revealed: $revealed, reviewed: $reviewed)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Palette.background)
        }
        .background(Palette.background.ignoresSafeArea())
    }
}

/// One card. The front shows the learner's sentence with the error blanked; the back adds the answer.
struct CardFace: View {
    let card: ReviewCard
    let revealed: Bool

    var body: some View {
        RaisedCard(accent: revealed ? Palette.leaf : Palette.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.front)
                    .font(.rounded(.title3, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if revealed {
                    Divider()
                    Text(card.back)
                        .font(.rounded(.title3, weight: .heavy))
                        .foregroundStyle(Palette.leaf)
                        .fixedSize(horizontal: false, vertical: true)
                    if !card.explanation.isEmpty {
                        Text(card.explanation)
                            .font(.rounded(.subheadline, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .frame(minHeight: 150, alignment: .topLeading)
        }
    }
}

/// Every card, with review, add and delete. Reached from the Progress tab.
struct MistakeDeckView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        let cards = model.allCards
        let dueCount = model.dueCards.count
        List {
            Group {
            Section {
                NavigationLink {
                    StandaloneReviewView()
                        .navigationTitle("Review")
                } label: {
                    Label(dueCount == 0 ? "Nothing due right now" : "Review \(dueCount) due", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(dueCount == 0)
            } footer: {
                Text(ActiveLanguage.pack.sources[.exchange].map { "Mistakes from your writing are added automatically. Add your \($0.shortName) partner's corrections with +." }
                     ?? "Add corrections from a tutor, a partner or your own checking with +, and review them here.")
            }
            if cards.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No cards yet", systemImage: "rectangle.stack")
                    } description: {
                        Text(ActiveLanguage.pack.sources[.exchange].map { "When a writing task is corrected, each mistake becomes a card here. Tap + to add a correction from your \($0.shortName) partner." }
                             ?? "Tap + to add a correction, from a tutor, a partner or your own checking. Each one becomes a card that comes back just before you'd forget it.")
                    }
                }
            }
            Section(cards.isEmpty ? "" : "\(cards.count) cards") {
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front.components(separatedBy: "\n").first ?? card.front)
                            .font(.rounded(.subheadline, weight: .bold))
                        Text(card.back.components(separatedBy: "\n").first ?? card.back)
                            .font(.rounded(.subheadline, weight: .semibold))
                            .foregroundStyle(Palette.leaf)
                        Text(card.due <= .now ? "Due now" : "Next \(card.due.formatted(.relative(presentation: .named)))")
                            .font(.rounded(.caption, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { model.deleteCard(cards[index]) }
                }
            }
            }
            .polyplotRows()
        }
        .polyplotListBackground()
        .navigationTitle("Mistake deck")
        .toolbar {
            Button("Add", systemImage: "plus") { adding = true }
        }
        .sheet(isPresented: $adding) {
            AddCardSheet(origin: "manual")
                .presentationDetents([.medium, .large])
        }
    }
}

/// Saves a correction (e.g. from a Tandem partner) as a card.
struct AddCardSheet: View {
    let origin: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var wrong = ""
    @State private var right = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
                Section("What you said or wrote") {
                    TextField("Yo soy cansado", text: $wrong, axis: .vertical)
                }
                Section("The correct version") {
                    TextField("Yo estoy cansado", text: $right, axis: .vertical)
                }
                Section("Why (optional)") {
                    TextField("Estar for temporary states", text: $note, axis: .vertical)
                }
                }
                .polyplotRows()
            }
            .polyplotListBackground()
            .navigationTitle("Add a correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addCard(wrong: wrong, right: right, note: note, origin: origin)
                        dismiss()
                    }
                    .disabled(wrong.trimmingCharacters(in: .whitespaces).isEmpty || right.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
