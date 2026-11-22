import Foundation
import Testing
@testable import PolyplotCore

/// "Other language": a language the learner names, planned only from their own sources (docs/09-multi-language.md §9.10).
@Suite struct CustomLanguageTests {
    let planner = DayPlanner(calendar: TestCalendar.utc)
    let today = TestCalendar.day(2026, 10, 26)

    func everyType() -> [CustomSource] {
        [CustomSource(name: "Podcast", strand: .input, minMinutes: 5, maxMinutes: 40),
         CustomSource(name: "Tutor chat", strand: .output, minMinutes: 10, maxMinutes: 20),
         CustomSource(name: "Easy reading", strand: .fluency, minMinutes: 5, maxMinutes: 15),
         CustomSource(name: "Textbook", strand: .languageFocused, minMinutes: 10, maxMinutes: 20)]
    }

    @Test func codesArePrivateUseAndNeverLost() {
        let code = LanguagePack.newCustomCode()
        #expect(code.hasPrefix("x-") && code.count == 10)
        #expect(LanguagePack.isCustom(code) && !LanguagePack.isCustom("es"))
        #expect(code != LanguagePack.newCustomCode())
        // Before it's registered, it's still that language (not Spanish), just unnamed.
        let unregistered = LanguagePack.pack(for: "x-unknown1")
        #expect(unregistered.code == "x-unknown1" && unregistered.isCustom)
        #expect(unregistered.flag == LanguagePack.defaultCustomFlag)
        #expect(LanguagePack.pack(for: "zz").code == "es", "a real unknown code still falls back to Spanish")
    }

    @Test func registeredLanguagesAreFoundByCode() {
        let code = LanguagePack.newCustomCode()
        LanguagePack.register(.custom(code: code, name: " Welsh ", flag: "🏴"))
        let pack = LanguagePack.pack(for: code)
        #expect(pack.name == "Welsh" && pack.nativeName == "Welsh" && pack.flag == "🏴")
        #expect(LanguagePack.registeredCustom.contains { $0.code == code })
        #expect(!LanguagePack.all.contains { $0.code == code }, "never one of the built-in languages")
    }

    @Test func itsBuiltInSourcesAreTheOnesThatWorkForAnyLanguage() {
        let pack = LanguagePack.custom(code: "x-test0001", name: "Welsh", flag: "🏴")
        #expect(pack.roles == [.drillApp, .writing, .exchange] && pack.course == nil && pack.series == nil && pack.graded == nil)
        #expect(pack.drill == LanguagePack.spanish.drill)
        #expect(pack.sources[.exchange]?.what.contains("Welsh") == true)
        #expect(pack.phrases == Phrasebook.english)
        // French's hours, a little above Spanish's: an added language is more likely to be a harder one.
        #expect(pack.levels == LanguagePack.french.levels)
        // Checked only by AI, told the learner's name for the language; never by the basic checker.
        #expect(pack.tutor.languageToolCode == nil && !pack.tutor.allowsBasicChecker)
        #expect(LanguagePack.spanish.tutor.allowsBasicChecker && LanguagePack.french.tutor.allowsBasicChecker)
        #expect(pack.tutor.instructions(language: pack.name, band: .a2_1, maximumErrors: 5).contains("Welsh tutor"))
        // Writing and exchanges keep their weekly targets; the other anchors belong to sources it doesn't have.
        for band in Band.allCases {
            let spanish = LanguagePack.spanish.anchorTargets(for: band)
            #expect(pack.anchorTargets(for: band) == AnchorTargets(writing: spanish.writing, exchanges: spanish.exchanges))
        }
    }

    @Test func sharedWordingFillsWithItsName() {
        let pack = LanguagePack.custom(code: "x-test0002", name: "Welsh", flag: "🏴")
        let shared = Band.allCases.flatMap { CanDo.statements(for: $0, pack: pack) }
            + Prompts.travelMissions.map(pack.fill) + Prompts.fluencyStories.map(pack.fill)
            + Prompts.writingPrompts.values.flatMap { $0 }.map(pack.fill)
        #expect(shared.allSatisfy { !$0.contains("{") }, "\(shared.filter { $0.contains("{") }.prefix(3))")
        #expect(shared.contains { $0.contains("Welsh") })
    }

    @Test(arguments: Band.allCases)
    func plansAreMadeOnlyFromTheLearnersSources(band: Band) {
        let pack = LanguagePack.custom(code: "x-test0003", name: "Welsh", flag: "🏴")
        let learner = LearnerSnapshot(band: band, customSources: everyType(), pack: pack)
        for budget in DayPlanner.budgetChoices {
            let plan = planner.plan(budget: budget, learner: learner, history: [], today: today)
            #expect(!plan.tasks.isEmpty, "\(band.rawValue) \(budget) min")
            #expect(plan.tasks.allSatisfy { $0.kind.isCustom || [.writing, .drillApp, .exchange].contains($0.kind.source) }, "\(band.rawValue) \(budget) min: \(plan.kinds)")
            #expect(plan.totalMinutes <= budget)
            #expect(plan.totalMinutes >= budget - 5, "\(band.rawValue) \(budget) min planned only \(plan.totalMinutes)")
        }
    }

    @Test func aMissingTypeHasItsShareSpreadOverTheOthers() {
        let pack = LanguagePack.custom(code: "x-test0004", name: "Welsh", flag: "🏴")
        let listeningOnly = [CustomSource(name: "Podcast", strand: .input, minMinutes: 10, maxMinutes: 60)]
        let learner = LearnerSnapshot(band: .b1_1, enabledSources: [], customSources: listeningOnly, pack: pack)
        #expect(learner.strandTargets[.input] == 1)
        let plan = planner.plan(budget: 30, learner: learner, history: [], today: today)
        #expect(plan.kinds == [.customInput] && plan.totalMinutes == 30)
    }

    @Test func missingTypesAreListedInSetupOrder() {
        #expect(CustomSource.missingStrands([]) == [.input, .output, .fluency, .languageFocused])
        #expect(CustomSource.missingStrands(everyType()).isEmpty)
        var sources = everyType()
        sources[1].isEnabled = false
        sources[3].name = " "
        #expect(CustomSource.missingStrands(sources) == [.output, .languageFocused])
        #expect(CustomSource.missingStrands(sources, covered: [.output]) == [.languageFocused], "Polyplot's writing fills speaking & writing")
    }
}

@Suite struct WritingPlaceholderTests {
    /// The writing box's placeholder is in the language being learned, never Spanish for everyone.
    @Test func eachLanguageHasItsOwn() {
        #expect(LanguagePack.spanish.phrases.writeHere == "Escribe aquí…")
        #expect(LanguagePack.french.phrases.writeHere == "Écris ici…")
        #expect(LanguagePack.custom(code: "x-test0009", name: "Welsh", flag: "🏴").phrases.writeHere == "Write here…")
        // A complete beginner sees it in English, like the other interface words.
        #expect(LanguagePack.spanish.phrases(for: .a1_1).writeHere == "Write here…")
        #expect(LanguagePack.spanish.phrases(for: .a2_1).writeHere == "Escribe aquí…")
    }
}
