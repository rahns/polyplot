import PolyplotCore
import SwiftUI

/// First launch, about 2 minutes. See docs/03-experience.md §3.4.
struct OnboardingView: View {
    /// Setting up a second language: the language is already chosen (Settings → Language) and the name
    /// is known, so it starts at the sources, with a Cancel back to the language already set up.
    let addingLanguage: Bool
    let onFinish: (OnboardingDraft) -> Void

    init(addingLanguage: Bool = false, onFinish: @escaping (OnboardingDraft) -> Void) {
        self.addingLanguage = addingLanguage
        self.onFinish = onFinish
        // An "Other language" added from Settings starts by naming it.
        _step = State(initialValue: addingLanguage ? (LanguagePack.isCustom(ActiveLanguage.code) ? .customLanguage : .sources) : .welcome)
    }

    @Environment(AppModel.self) private var model
    @State private var draft = OnboardingDraft()
    @State private var importing = false
    @State private var restoreError: String?
    @State private var step: Step
    @State private var canDoIndex = 0
    /// "Other language": the source being added or edited, and the warning about types left empty.
    @State private var editingSource: CustomSource?
    @State private var confirmingMissingTypes = false
    /// Scrolls the step to a part of it that's below the screen (the classes step's "Each day").
    @State private var scrollTarget: String?

    enum Step: Int, CaseIterable {
        // The goal comes after placement, so the weekly goal and target date can be worked out from your hours.
        // "Other language" adds naming it (customLanguage) and choosing its balance; its sources are its own.
        case welcome, language, customLanguage, name, sources, lessons, progress, canDo, placement, balance, goal, feedback, habit
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                header
            }
            ScrollViewReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(step)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollBounceBehavior(.basedOnSize)
                // New options appearing below the screen flash the scroll bar, so it's clear there's more.
                .scrollIndicatorsFlash(trigger: draft.lessonSchedule.days.count)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            footer
        }
        .background(Palette.background.ignoresSafeArea())
        .onAppear {
            // Adding a language (chosen in Settings → Language): the language is already picked and the
            // learner's name is known, so setup starts at the sources.
            if addingLanguage, let existing = model.profiles.first {
                draft.languageCode = model.languageCode
                draft.name = existing.displayName
                draft.weekStartsOnSunday = existing.weekStartsOnSunday
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .sheet(isPresented: $importing) {
            BackupImportPicker { result in
                importing = false
                switch result {
                case .success(let data):
                    do {
                        try withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            try model.restore(from: data)
                        }
                    } catch {
                        restoreError = error.localizedDescription
                    }
                case .failure(let error): restoreError = error.localizedDescription
                case nil: break
                }
            }
            .ignoresSafeArea()
        }
        .alert(restoreError ?? "", isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $editingSource) { source in
            CustomSourceEditor(source: source, isNew: !draft.customSources.contains { $0.id == source.id }) { saved in
                if let index = draft.customSources.firstIndex(where: { $0.id == saved.id }) {
                    draft.customSources[index] = saved
                } else {
                    draft.customSources.append(saved)
                }
            }
        }
        .confirmationDialog(missingTypesTitle, isPresented: $confirmingMissingTypes, titleVisibility: .visible) {
            Button("Add sources first", role: .cancel) {}
            Button("Continue anyway") { go(to: neighbour(of: step, by: 1) ?? .habit) }
        } message: {
            Text("Your plan can only use the types you have sources for, so their time goes to the others, and some research-backed parts of learning are left out. You can add sources any time in Settings → Sources → Custom sources.")
        }
    }

    /// An "Other language"'s study types with nothing to plan: no source of the learner's and no built-in
    /// one switched on (writing and an exchange partner for speaking & writing, Duolingo for grammar & vocab).
    private var missingTypes: [Strand] {
        let covered = Set(Self.builtIns.filter { draft.sources.contains($0.role) }.map(\.strand))
        return CustomSource.missingStrands(draft.customSources, covered: covered)
    }

    /// The built-in sources an "Other language" has, the study type each fills, and how it's described there.
    private static let builtIns: [(role: SourceKind, strand: Strand, title: String, subtitle: (String) -> String)] = [
        (.exchange, .output, "Tandem/HelloTalk partner", { "Messages, then voice notes and calls, with a native \($0) speaker" }),
        (.writing, .output, "Polyplot's writing tasks", { "Guided writing in \($0), checked by AI with your own free key" }),
        (.drillApp, .languageFocused, "Duolingo", { "A short daily warm-up, if Duolingo teaches \($0). Add another grammar & vocab source too, such as a textbook or grammar lessons on YouTube: a few minutes of Duolingo isn't enough on its own." }),
    ]

    /// "No source for fluency practice or grammar & vocab".
    private var missingTypesTitle: String {
        let names = missingTypes.map { $0.label.lowercased() }
        guard let last = names.last else { return "" }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + last : last
        return "No source for \(list)"
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                go(to: neighbour(of: step, by: -1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.rounded(.headline, weight: .heavy))
                    .foregroundStyle(Palette.secondaryText)
            }
            .accessibilityLabel("Back")
            .opacity(step == firstStep ? 0 : 1)
            .disabled(step == firstStep)
            ChunkyProgressBar(value: Double(step.rawValue) / Double(Step.allCases.count - 1), color: Palette.leaf)
            // Setting up another language can be called off: back to the one already being learned.
            if addingLanguage, let existing = model.profiles.first {
                Button("Cancel") { model.setLanguage(existing.languageCode) }
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var footer: some View {
        if step != .canDo {
            Button(step == .habit ? "Let's go" : step == .welcome ? "Start"
                   : step == .feedback && draft.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip for now" : "Continue") {
                advance()
            }
            .buttonStyle(ChunkyButtonStyle(color: step == .habit ? Palette.leaf : Palette.coral))
            .disabled((step == .sources && !draft.isCustomLanguage && draft.sources.isEmpty)
                      || (step == .customLanguage && draft.customLanguageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                      // "Yes" to classes needs at least one day.
                      || (step == .lessons && draft.hasLessons && draft.lessonSchedule.isEmpty))
            .padding(20)
        }
    }

    private func advance() {
        if step == .habit {
            if !draft.geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { GeminiKey.save(draft.geminiKey) }
            onFinish(draft)
            return
        }
        // A language that's already set up (reached from Settings → Language) is switched to, not set up twice.
        if step == .language, model.profiles.contains(where: { $0.languageCode == draft.languageCode }) {
            model.setLanguage(draft.languageCode)
            return
        }
        if step == .progress {
            canDoIndex = 0
            draft.canDoAnswers = [:]
        }
        // An "Other language" can go on without a source of every type, but is warned first.
        if step == .sources, draft.isCustomLanguage, !missingTypes.isEmpty {
            confirmingMissingTypes = true
            return
        }
        go(to: neighbour(of: step, by: 1) ?? .habit)
    }

    /// AI writing keys are shared by every language (they're in the Keychain), so adding a language
    /// skips the writing-feedback step when one is already set up.
    private var skipsFeedback: Bool {
        addingLanguage && (GeminiKey.current != nil || GroqKey.current != nil)
    }

    /// The next or previous step, passing over the ones this setup skips.
    private func neighbour(of step: Step, by offset: Int) -> Step? {
        var next = Step(rawValue: step.rawValue + offset)
        // Someone starting from zero has no can-do questions to answer: they start at A1.1.
        // Naming the language and choosing its balance are for an "Other language" only.
        while (next == .feedback && skipsFeedback) || (next == .canDo && draft.startingFromZero)
                || ((next == .customLanguage || next == .balance) && !draft.isCustomLanguage)
                // Adding a language: the learner's name is already known.
                || (next == .name && addingLanguage) {
            next = Step(rawValue: next!.rawValue + offset)
        }
        return next
    }

    /// Where setup starts: the welcome on first launch, the sources when adding a language.
    private var firstStep: Step { addingLanguage ? (draft.isCustomLanguage ? .customLanguage : .sources) : .welcome }

    private func go(to newStep: Step) {
        if newStep == .goal { draft.prepareGoal() }
        // The own-balance sliders start from the level's split, until the learner moves them.
        if newStep == .balance && !draft.usesOwnBalance { draft.ownBalance = StrandBalance(band: draft.placement.band) }
        step = newStep
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .language: language
        case .customLanguage: customLanguage
        case .name: name
        case .goal: goal
        case .sources: sources
        case .lessons: lessons
        case .progress: progress
        case .canDo: canDo
        case .placement: placement
        case .balance: balance
        case .feedback: feedback
        case .habit: habit
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            // Poly introduces himself, so new learners know who the toucan is.
            PolySpeechBubble(text: "Hi! I'm Poly 👋 I'll turn the language learning you already do into one simple plan each day, and cheer you on.")
                .padding(.horizontal, 12)
            PolyBadge(size: 110)
            Text("Polyplot")
                .font(.rounded(.largeTitle, weight: .black))
                .foregroundStyle(Palette.ink)
            Text("Polyplot turns the apps, courses and shows you already use into one plan, and tells you exactly what to do each day.")
                .font(.rounded(.title3, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
            Text("Setting up takes about two minutes.")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.coral)
            Button("Restore from a backup") { importing = true }
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// What's being learned. Everything after this step follows the choice: the sources offered, the hours
    /// each level needs, and the app's wording.
    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle("What are you learning?")
            Text("Polyplot builds your plan around the best sources for that language.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            ForEach(LanguagePack.all) { pack in
                let chosen = draft.languageCode == pack.code
                Button {
                    draft.languageCode = pack.code
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.name).font(.rounded(.headline, weight: .bold))
                            Text(pack.nativeName).font(.rounded(.caption, weight: .medium)).foregroundStyle(Palette.secondaryText)
                        }
                        .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .font(.title)
                            .foregroundStyle(chosen ? Palette.leaf : Palette.secondaryText)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chosen ? "\(pack.name), chosen" : pack.name)
            }
            // Any other language, planned from the learner's own sources.
            Button {
                if !draft.isCustomLanguage { draft.languageCode = LanguagePack.newCustomCode() }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other language").font(.rounded(.headline, weight: .bold))
                        Text("Any language, planned from sources you add").font(.rounded(.caption, weight: .medium)).foregroundStyle(Palette.secondaryText)
                    }
                    .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    Image(systemName: draft.isCustomLanguage ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(draft.isCustomLanguage ? Palette.leaf : Palette.secondaryText)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.isCustomLanguage ? "Other language, chosen" : "Other language")
            ForEach(LanguagePack.upcoming, id: \.self) { name in
                HStack {
                    Text(name).font(.rounded(.headline, weight: .bold))
                    Spacer()
                    Text("Coming soon").font(.rounded(.caption, weight: .bold))
                }
                .foregroundStyle(Palette.secondaryText)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card.opacity(0.5)))
            }
        }
        .sensoryFeedback(.selection, trigger: draft.languageCode)
    }

    // MARK: Other language

    /// Naming an "Other language" and picking its emoji.
    private var customLanguage: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle("Which language?")
            Text("Polyplot has no courses or shows made for it, so your plan is built from sources you add next (podcasts, a course, a tutor, anything you use), plus Duolingo, a language exchange partner and Polyplot's writing if you want them.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            TextField("Language, e.g. Welsh", text: $draft.customLanguageName)
                .textInputAutocapitalization(.words)
                .font(.rounded(.title3, weight: .semibold))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
            Text("Pick an emoji for it")
                .font(.rounded(.headline, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)
            EmojiPicker(selection: $draft.customLanguageFlag)
        }
    }

    /// An "Other language"'s sources: one card per study type, each saying what's expected of it.
    private var customSources: some View {
        let name = draft.pack.name
        return VStack(alignment: .leading, spacing: 14) {
            StepTitle("Add your \(name) sources")
            Text("Your plan is made from these. Have at least one of each type, so every day can mix listening, speaking & writing, fluency practice and grammar & vocab. You can change them any time in Settings → Sources.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            ForEach(CustomSource.setupOrder, id: \.self) { strand in
                customTypeCard(strand)
            }
        }
    }

    private func customTypeCard(_ strand: Strand) -> some View {
        let added = draft.customSources.filter { $0.strand == strand }
        let builtIns = Self.builtIns.filter { $0.strand == strand }
        let builtInOn = builtIns.contains { draft.sources.contains($0.role) }
        return RaisedCard(accent: strand.color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: TaskCopy.symbol(for: TaskKind.custom(for: strand)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(strand.color))
                    Text(strand.label)
                        .font(.rounded(.headline, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                }
                Text(strand.ownSourceExpectation)
                    .font(.rounded(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // Listening matters most: about half of every plan, and there's no built-in source for it here.
                if strand == .input {
                    Label("The most important type: listening makes up about half of every plan, and understanding lots of \(draft.pack.name) is what moves your level most. Add at least one listening source.",
                          systemImage: "star.fill")
                        .font(.rounded(.caption, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(strand.color.opacity(0.15)))
                }
                ForEach(added) { source in
                    HStack(spacing: 10) {
                        Button {
                            editingSource = source
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.name)
                                    .font(.rounded(.body, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text(CustomSourcesView.rangeText(source.minuteRange))
                                    .font(.rounded(.caption, weight: .medium))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.snappy) { draft.customSources.removeAll { $0.id == source.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(source.name)")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.background))
                }
                // Built-in sources that fill this type: an exchange partner and writing, or Duolingo.
                ForEach(builtIns, id: \.role) { builtIn in
                    let on = draft.sources.contains(builtIn.role)
                    Button {
                        if on { draft.sources.remove(builtIn.role) } else { draft.sources.insert(builtIn.role) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(builtIn.title)
                                    .font(.rounded(.body, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                Text(builtIn.subtitle(draft.pack.name))
                                    .font(.rounded(.caption, weight: .medium))
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(on ? Palette.leaf : Palette.secondaryText)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.background))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Using \(builtIn.title)" : "Not using \(builtIn.title)")
                    .sensoryFeedback(.selection, trigger: on)
                }
                if added.isEmpty && !builtInOn {
                    Label("No source yet. Without one, this part of learning is left out of your plan.", systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Palette.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    editingSource = Self.newSource(strand)
                } label: {
                    Label(added.isEmpty ? "Add a source" : "Add another", systemImage: "plus")
                }
                .buttonStyle(ChunkySecondaryButtonStyle())
            }
        }
        .animation(.snappy, value: added)
    }

    /// A new source of this type, with a length that suits it.
    private static func newSource(_ strand: Strand) -> CustomSource {
        let range: (Int, Int) = switch strand {
        case .input: (15, 40)
        case .output: (10, 20)
        case .fluency: (5, 15)
        case .languageFocused: (10, 20)
        }
        return CustomSource(name: "", strand: strand, minMinutes: range.0, maxMinutes: range.1)
    }

    /// Polyplot's split for each level, or the learner's own for this language.
    private var balance: some View {
        let band = draft.placement.band
        let standard = StrandBalance(band: band)
        let order: [Strand] = [.input, .languageFocused, .output, .fluency]
        return VStack(alignment: .leading, spacing: 14) {
            StepTitle("How should your time be split?")
            Text("Each day's plan shares your time between listening, grammar & vocab, speaking & writing and fluency practice.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            balanceChoice(chosen: !draft.usesOwnBalance, title: "Polyplot's balance for each level",
                          note: "Recommended",
                          text: "Based on research for each stage of learning: Paul Nation's four strands (meaning-focused input, meaning-focused output, language-focused study and fluency), Stephen Krashen's work on comprehensible input and Merrill Swain's on output. It shifts as you level up: more grammar & vocab at the start, more speaking & writing later, and listening about half your time throughout. At \(band.rawValue): " + order.map { "\($0.label) \(standard[$0])%" }.joined(separator: " · ") + ".") {
                draft.usesOwnBalance = false
            }
            balanceChoice(chosen: draft.usesOwnBalance, title: "Set my own balance", note: nil,
                          text: "Your own split for this language. It stays as you set it at every level.") {
                draft.usesOwnBalance = true
            }
            if draft.usesOwnBalance {
                RaisedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        BalanceBar(balance: draft.ownBalance, order: order)
                        ForEach(order, id: \.self) { strand in
                            StrandSliderRow(strand: strand, percent: draft.ownBalance[strand], enabled: true,
                                            warning: missingTypes.contains(strand) && draft.ownBalance[strand] > 0
                                                ? "You have no source for this yet, so its share goes to the others until you add one."
                                                : nil) { value in
                                draft.ownBalance.set(strand, to: value)
                            } onRelease: {}
                        }
                    }
                }
                .transition(.opacity)
            }
            Text("You can change this any time in Settings → Plan balance.")
                .font(.rounded(.caption, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
        }
        .animation(.snappy, value: draft.usesOwnBalance)
    }

    private func balanceChoice(chosen: Bool, title: String, note: String?, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(chosen ? Palette.leaf : Palette.secondaryText)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.rounded(.headline, weight: .bold)).foregroundStyle(Palette.ink)
                        if let note {
                            Text(note)
                                .font(.rounded(.caption2, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.leaf))
                        }
                    }
                    Text(text)
                        .font(.rounded(.caption, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: chosen)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle("What should I call you?")
            TextField("Your name (optional)", text: $draft.name)
                .textContentType(.givenName)
                .font(.rounded(.title3, weight: .semibold))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
        }
    }

    private var goal: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle("Where are you heading?")
            Text("Pick your goal, then either how much time you'll give it each week or when you want to get there. You can change this any time in Settings → Goal.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            GoalEditor(goal: $draft.goal, weeklyMinutes: $draft.weeklyGoalMinutes, targetDate: $draft.targetDate,
                       currentHours: draft.trainingHours, band: draft.placement.band)
        }
    }

    @ViewBuilder
    private var sources: some View {
        if draft.isCustomLanguage { customSources } else { builtInSources }
    }

    private var builtInSources: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle("Which sources do you want to use?")
            Text("Tick the ones you use already or want to start; Polyplot builds your plan from those. Not sure what one is? Tap it.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            ForEach(draft.pack.roles, id: \.self) { source in
                SourceToggleRow(source: source, isOn: Binding(
                    get: { draft.sources.contains(source) },
                    set: { on in
                        if on { draft.sources.insert(source) } else { draft.sources.remove(source) }
                    }
                ))
            }
        }
    }

    /// Classes or a tutor on set days: always in that day's plan, at its usual length. Each day's own length
    /// and type can be set later in Settings → Classes/Tutoring.
    private var lessons: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle("Do you have classes or a tutor?")
            Text("A class or tutoring session on set days is always in that day's plan, and the rest of the day balances around it.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            HStack(spacing: 10) {
                ChipButton(title: "Not right now", isSelected: !draft.hasLessons) { draft.hasLessons = false }
                ChipButton(title: "Yes", isSelected: draft.hasLessons) { draft.hasLessons = true }
            }
            if draft.hasLessons {
                Text("Which days?")
                    .font(.rounded(.headline, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                    ForEach(draft.weekStartsOnSunday ? Array(1...7) : [2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        ChipButton(title: Calendar.current.shortWeekdaySymbols[weekday - 1], isSelected: draft.lessonSchedule.days[weekday] != nil) {
                            if draft.lessonSchedule.days[weekday] == nil {
                                draft.lessonSchedule.days[weekday] = .init()
                            } else {
                                draft.lessonSchedule.days[weekday] = nil
                            }
                        }
                    }
                }
                // With two or more days, each can have its own length and kind further down: say so, and go there on a tap.
                if draft.lessonSchedule.days.count > 1 {
                    Button {
                        scrollTarget = "eachDay"
                    } label: {
                        Label("Different days, different lengths or kinds? Set each day below", systemImage: "arrow.down.circle.fill")
                            .font(.rounded(.subheadline, weight: .bold))
                            .foregroundStyle(Palette.sky)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                RaisedCard {
                    NumberStepper(title: "Usual length (min)", value: $draft.lessonSchedule.usualMinutes, range: 15...180, step: 5)
                }
                Text("What kind is it usually?")
                    .font(.rounded(.headline, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                    ForEach(LessonType.allCases, id: \.self) { type in
                        ChipButton(title: TaskCopy.lessonTypeName(type), isSelected: draft.lessonSchedule.usualType == type,
                                   color: TaskKind.lesson(for: type).color) { draft.lessonSchedule.usualType = type }
                    }
                }
                Text("It decides which part of your practice it counts toward. All-in-one splits it evenly between speaking & writing, listening and grammar & vocab.")
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // With more than one day, any day can have its own length and kind, as in Settings.
                let chosen = (draft.weekStartsOnSunday ? Array(1...7) : [2, 3, 4, 5, 6, 7, 1]).filter { draft.lessonSchedule.days[$0] != nil }
                if chosen.count > 1 {
                    Text("Each day")
                        .font(.rounded(.headline, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .id("eachDay")
                    Text("Give a day its own length or kind, e.g. a longer speaking class on Tuesdays and a shorter grammar session on Thursdays.")
                        .font(.rounded(.caption, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(chosen, id: \.self) { weekday in
                        lessonDayCard(weekday)
                    }
                }
            }
        }
        .animation(.snappy, value: draft.hasLessons)
    }

    /// One lesson day: the usual length and kind, or its own.
    private func lessonDayCard(_ weekday: Int) -> some View {
        let schedule = draft.lessonSchedule
        let day = schedule.days[weekday] ?? .init()
        let custom = day.minutes != nil || day.type != nil
        return RaisedCard(accent: TaskKind.lesson(for: day.type ?? schedule.usualType).color) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { !custom },
                    set: { same in
                        draft.lessonSchedule.days[weekday] = same ? .init() : .init(minutes: schedule.usualMinutes, type: schedule.usualType)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Calendar.current.weekdaySymbols[weekday - 1])
                            .font(.rounded(.headline, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                        Text(custom ? "Its own length and kind" : "Same as usual: \(schedule.usualMinutes) min · \(TaskCopy.lessonTypeName(schedule.usualType))")
                            .font(.rounded(.caption, weight: .semibold))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .tint(Palette.leaf)
                if custom {
                    NumberStepper(title: "Length (min)", value: Binding(
                        get: { draft.lessonSchedule.days[weekday]?.minutes ?? schedule.usualMinutes },
                        set: { draft.lessonSchedule.days[weekday]?.minutes = $0 }
                    ), range: 15...180, step: 5)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                        ForEach(LessonType.allCases, id: \.self) { type in
                            ChipButton(title: TaskCopy.lessonTypeName(type), isSelected: (day.type ?? schedule.usualType) == type,
                                       color: TaskKind.lesson(for: type).color) { draft.lessonSchedule.days[weekday]?.type = type }
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: custom)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle("Where are you now?")
            Text(draft.startingFromZero
                 ? "Polyplot will start you at the very beginning."
                 : draft.isCustomLanguage ? "A rough guess is fine. It's what Polyplot uses to place you."
                 : "Check each app for these numbers. They're what Polyplot uses to place you.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            // Complete beginners skip the numbers (and the can-do questions): they start at A1.1.
            Button {
                withAnimation(.snappy) { draft.startingFromZero.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: draft.startingFromZero ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(draft.startingFromZero ? Palette.leaf : Palette.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I'm completely new to \(draft.pack.name)")
                            .font(.rounded(.headline, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Text("Start from the very first words")
                            .font(.rounded(.caption, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: draft.startingFromZero)
            if !draft.startingFromZero {
                let pack = draft.pack
                if draft.importsHours, let graded = pack.graded {
                    RaisedCard(accent: Palette.coral) {
                        VStack(alignment: .leading, spacing: 10) {
                            SourceHeading(source: .gradedVideo)
                            NumberStepper(title: "Total hours watched", value: $draft.dreamingHours, range: 0...3000, step: 5)
                            NumberStepper(title: "Difficulty you're watching: \(draft.dreamingDifficultyLow)–\(draft.dreamingDifficultyLow + graded.windowWidth)",
                                          value: $draft.dreamingDifficultyLow,
                                          range: graded.scale.lowerBound...(graded.scale.upperBound - graded.windowWidth), step: 1)
                        }
                    }
                } else {
                    RaisedCard(accent: Palette.coral) {
                        NumberStepper(title: "Hours of \(pack.name) you've listened to or watched (roughly)", value: $draft.otherListeningHours, range: 0...3000, step: 10)
                    }
                }
                if draft.sources.contains(.audioCourse), let course = pack.course {
                    RaisedCard(accent: Palette.leaf) {
                        VStack(alignment: .leading, spacing: 10) {
                            SourceHeading(source: .audioCourse)
                            NumberStepper(title: "Last track finished", value: $draft.languageTransferLastTrack, range: 0...course.tracks, step: 1)
                        }
                    }
                }
                if draft.sources.contains(.drillApp), let drill = pack.drill {
                    RaisedCard(accent: Palette.leaf) {
                        VStack(alignment: .leading, spacing: 10) {
                            SourceHeading(source: .drillApp)
                            NumberStepper(title: "Section", value: $draft.duolingoSection, range: drill.sections, step: 1)
                            NumberStepper(title: "Unit", value: $draft.duolingoUnit, range: drill.units, step: 1)
                        }
                    }
                }
                if draft.sources.contains(.learnerSeries), let series = pack.series {
                    RaisedCard(accent: Palette.coral) {
                        VStack(alignment: .leading, spacing: 10) {
                            SourceHeading(source: .learnerSeries)
                            NumberStepper(title: "Episodes watched", value: $draft.extraEpisodesWatched, range: 0...series.episodes, step: 1)
                        }
                    }
                }
            }
        }
    }

    private var canDo: some View {
        let statements = draft.canDoStatements
        return VStack(alignment: .leading, spacing: 20) {
            StepTitle("Can you do this in \(draft.pack.name)?")
            Text("\(min(canDoIndex + 1, statements.count)) of \(statements.count)")
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(Palette.secondaryText)
            if canDoIndex < statements.count {
                let statement = statements[canDoIndex]
                RaisedCard(accent: Palette.sky) {
                    Text(statement.text)
                        .font(.rounded(.title2, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 140, alignment: .topLeading)
                }
                .id(statement.text)
                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                HStack(spacing: 12) {
                    Button(draft.pack.phrases(for: draft.bandByHours).notYet) { answer(statement.text, false) }
                        .buttonStyle(ChunkySecondaryButtonStyle())
                    Button(draft.pack.phrases(for: draft.bandByHours).yes) { answer(statement.text, true) }
                        .buttonStyle(ChunkyButtonStyle(color: Palette.leaf))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: canDoIndex)
    }

    private func answer(_ statement: String, _ yes: Bool) {
        draft.canDoAnswers[statement] = yes
        canDoIndex += 1
        if canDoIndex >= draft.canDoStatements.count {
            go(to: .placement)
        }
    }

    private var placement: some View {
        let result = draft.placement
        return VStack(spacing: 18) {
            Spacer(minLength: 30)
            PolyBadge(size: 80)
            Text("You're starting as")
                .font(.rounded(.title3, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            BandBadge(band: result.band)
                .transition(.scale.combined(with: .opacity))
            Text(placementReason(result))
                .font(.rounded(.subheadline, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.success, trigger: step)
    }

    private func placementReason(_ result: Placement.Result) -> String {
        if draft.startingFromZero && draft.isCustomLanguage {
            return "Starting from zero, with short, easy sessions from your sources. The level-up check comes once you've put in the hours."
        }
        if draft.startingFromZero {
            return "Starting from zero: the easiest videos, the first course tracks and short daily lessons. The level-up check comes once you've put in the hours."
        }
        let yes = draft.canDoAnswers.values.filter { $0 }.count
        let base = "\(Int(draft.inputHours)) hours of listening (≈ \(Int(draft.trainingHours)) training hours, since listening is \(Int(Band.listeningShare * 100))% of Polyplot's mix) and \(yes) of \(draft.canDoStatements.count) can-dos"
        switch result.adjustment {
        case 1: return "\(base). You're ahead of your hours, so you start one level up."
        default: return "\(base)."
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(draft.isCustomLanguage ? "Writing feedback" : "Better writing feedback")
            Text(draft.isCustomLanguage
                 ? "Poly checks your \(draft.pack.name) writing with AI: Google's Gemini, for free, using your own API key. It finds your mistakes and explains each one. Polyplot's basic checker doesn't know \(draft.pack.name), so without a key your writing is saved but not checked. You can also do this later in Settings."
                 : "Poly can check your writing with Google's Gemini, for free, using your own API key. It catches more than the basic checker and explains each mistake. You can also do this later in Settings.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            GeminiKeySetup(key: $draft.geminiKey)
        }
    }

    private var habit: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle("When should Poly remind you?")
            Text("Pick the time you usually have for \(draft.pack.name). A regular time makes the habit stick.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Toggle(isOn: $draft.reminderEnabled.animation()) {
                Text("Daily reminder").font(.rounded(.body, weight: .semibold))
            }
            .tint(Palette.leaf)
            if draft.reminderEnabled {
                DatePicker("Time", selection: $draft.reminderTime, displayedComponents: .hourAndMinute)
                    .font(.rounded(.body, weight: .semibold))
            }
            StepTitle("Your week starts on")
            HStack(spacing: 10) {
                ChipButton(title: "Monday", isSelected: !draft.weekStartsOnSunday) { draft.weekStartsOnSunday = false }
                ChipButton(title: "Sunday", isSelected: draft.weekStartsOnSunday) { draft.weekStartsOnSunday = true }
            }
            Text("Your weekly goal resets at the start of each week.")
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
        }
        .task(id: draft.reminderEnabled) {
            if draft.reminderEnabled {
                _ = await Reminders.requestPermission()
            }
        }
    }
}

// MARK: - Pieces

struct StepTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.rounded(.title2, weight: .black))
            .foregroundStyle(Palette.ink)
    }
}

struct BandBadge: View {
    let band: Band

    var body: some View {
        VStack(spacing: 4) {
            Text(ActiveLanguage.pack.levelName(band))
                .font(.rounded(.largeTitle, weight: .black))
            Text(band.rawValue)
                .font(.rounded(.headline, weight: .heavy))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 36)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.coral))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.coral.edge()).offset(y: 5))
    }
}

struct SourceHeading: View {
    let source: SourceKind

    var body: some View {
        Label(SourceCopy.name(source), systemImage: SourceCopy.symbol(source))
            .font(.rounded(.headline, weight: .heavy))
            .foregroundStyle(Palette.ink)
    }
}

struct SourceToggleRow: View {
    let source: SourceKind
    @Binding var isOn: Bool
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 14) {
            // The source itself opens what it is; the tick on the right switches it on or off.
            Button {
                showingInfo = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: SourceCopy.symbol(source))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isOn ? .white : Palette.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? Palette.coral : Palette.lilac))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(SourceCopy.name(source)).font(.rounded(.headline, weight: .bold))
                            Image(systemName: "info.circle")
                                .font(.rounded(.caption, weight: .bold))
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Text(SourceCopy.role(source)).font(.rounded(.caption, weight: .medium)).foregroundStyle(Palette.secondaryText)
                    }
                    .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what \(SourceCopy.name(source)) is")
            Button {
                isOn.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(isOn ? Palette.leaf : Palette.secondaryText)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOn ? "Using \(SourceCopy.name(source))" : "Not using \(SourceCopy.name(source))")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.card))
        .sensoryFeedback(.selection, trigger: isOn)
        .sheet(isPresented: $showingInfo) { SourceInfoSheet(source: source) }
    }
}

struct NumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.rounded(.title3, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 70)
                .onChange(of: value) { _, new in value = min(max(new, range.lowerBound), range.upperBound) }
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

struct FlowChips: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                ChipButton(title: item, isSelected: selection == item) { selection = item }
            }
        }
    }
}

/// How the language being learned names each source (`LanguagePack.sources`).
enum SourceCopy {
    private static func info(_ source: SourceKind) -> SourceInfo? { ActiveLanguage.pack.sources[source] }

    static func name(_ source: SourceKind) -> String { info(source)?.name ?? "" }
    static func role(_ source: SourceKind) -> String { info(source)?.role ?? "" }
    static func symbol(_ source: SourceKind) -> String { info(source)?.symbol ?? "questionmark.circle" }
}

/// A big speech bubble with its tail pointing down at Poly, in a fixed dark ink on white so it reads in both modes.
struct PolySpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.rounded(.headline, weight: .bold))
            .foregroundStyle(Palette.inkOnBright)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.cardEdge).offset(y: 4))
            .overlay(alignment: .bottom) {
                Triangle()
                    .fill(.white)
                    .frame(width: 22, height: 12)
                    .offset(y: 11)
            }
            .padding(.bottom, 10)
    }
}

/// An emoji for an "Other language": a grid of flags and symbols, or any emoji typed in.
struct EmojiPicker: View {
    @Binding var selection: String
    @State private var typed = ""

    static let suggestions = ["🇩🇪", "🇮🇹", "🇵🇹", "🇧🇷", "🇳🇱", "🇸🇪", "🇳🇴", "🇩🇰", "🇫🇮", "🇵🇱", "🇬🇷", "🇹🇷",
                              "🇷🇺", "🇺🇦", "🇯🇵", "🇰🇷", "🇨🇳", "🇮🇳", "🇮🇱", "🇸🇦", "🇻🇳", "🇹🇭", "🇮🇩", "🇵🇭",
                              "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🇮🇪", "🌐", "🗣️", "📚", "🦜", "✨"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.suggestions, id: \.self) { emoji in
                    let chosen = selection == emoji
                    Button {
                        selection = emoji
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? Palette.leaf.opacity(0.25) : Palette.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosen ? Palette.leaf : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chosen ? "\(emoji), chosen" : emoji)
                }
            }
            HStack(spacing: 12) {
                Text("Or type any emoji")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                TextField("🙂", text: $typed)
                    .font(.system(size: 28))
                    .multilineTextAlignment(.center)
                    .frame(width: 64, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
                    .onChange(of: typed) { _, text in
                        guard let emoji = Self.lastEmoji(in: text) else {
                            if !text.isEmpty { typed = "" }
                            return
                        }
                        if typed != emoji { typed = emoji }
                        selection = emoji
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// The last emoji in `text` (a flag, a symbol, one with a skin tone…), ignoring letters and digits.
    static func lastEmoji(in text: String) -> String? {
        text.last { character in
            let scalars = character.unicodeScalars
            return scalars.contains { $0.properties.isEmojiPresentation }
                || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)
        }.map(String.init)
    }
}
