import Foundation
import Observation
import PolyplotCore

/// Answers collected during onboarding, applied to a new `LearnerProfile` at the end.
@MainActor
@Observable
final class OnboardingDraft {
    /// The language being set up, chosen on the first step. The rest of onboarding (sources, level hours,
    /// can-do questions) follows it; choosing it also makes it the language the app's wording uses.
    var languageCode = ActiveLanguage.code {
        didSet {
            ActiveLanguage.use(languageCode)
            sources = Set(pack.roles)
        }
    }
    /// The language's pack. An "Other language" is built from the name and emoji typed so far.
    var pack: LanguagePack {
        isCustomLanguage ? .custom(code: languageCode, name: customLanguageName, flag: customLanguageFlag) : LanguagePack.pack(for: languageCode)
    }

    /// "Other language": a language Polyplot has no pack for, planned only from the learner's own sources.
    var isCustomLanguage: Bool { LanguagePack.isCustom(languageCode) }
    var customLanguageName = "" { didSet { useCustomPack() } }
    var customLanguageFlag = LanguagePack.defaultCustomFlag { didSet { useCustomPack() } }
    /// The learner's own sources for an "Other language", added during setup.
    var customSources: [CustomSource] = []
    /// An "Other language" can keep Polyplot's research-based split for each level or start with its own.
    var usesOwnBalance = false
    var ownBalance = StrandBalance(band: .a2_1)

    /// Keeps the app's wording ("I'm completely new to Welsh") on the name being typed.
    private func useCustomPack() {
        guard isCustomLanguage else { return }
        LanguagePack.register(pack)
        ActiveLanguage.use(languageCode)
    }

    var name = ""
    var goal = "B2"
    /// Set from the weekly goal when the goal step first opens; the two stay linked from then on.
    var targetDate = Date.now
    var targetDateSet = false

    var sources: Set<SourceKind> = Set(ActiveLanguage.pack.roles)

    /// "I'm completely new": no hours, no source progress, no can-do questions; placed at A1.1.
    var startingFromZero = false

    var dreamingHours = 150
    var otherListeningHours = 150
    var dreamingDifficultyLow = 40
    var languageTransferLastTrack = 0
    var duolingoSection = 1
    var duolingoUnit = 1
    var extraEpisodesWatched = 0

    /// Answers to the can-do statements, keyed by statement.
    var canDoAnswers: [String: Bool] = [:]

    var reminderEnabled = true
    var reminderTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 30)) ?? .now
    var weeklyGoalMinutes = 150
    var weekStartsOnSunday = false
    /// Saved to the Keychain when onboarding finishes, not to the profile.
    var geminiKey = ""


    /// Whether the graded video library keeps the learner's hours (Dreaming Spanish does), so they can be read off it.
    var importsHours: Bool { sources.contains(.gradedVideo) && pack.graded?.countsHours == true }

    /// Listening hours before Polyplot (the graded library's counter, or an estimate).
    var inputHours: Double {
        if startingFromZero { return 0 }
        return Double(importsHours ? dreamingHours : otherListeningHours)
    }

    /// Listening before Polyplot as training hours (÷ the listening share), which is what levels are measured in.
    var trainingHours: Double { Band.trainingHours(fromListening: inputHours) }

    var bandByHours: Band { pack.levels.band(forHours: trainingHours) }

    /// The first time the goal step opens: the date the default weekly goal leads to.
    func prepareGoal() {
        guard !targetDateSet else { return }
        // A beginner's first goal is A2: B2 would be years away, which isn't a motivating first target.
        if placement.band < .a2_1 && goal == "B2" { goal = "A2" }
        targetDate = GoalPace.arrival(atHours: pack.levels.threshold(GoalEditor.goalBand(for: goal)), currentHours: trainingHours,
                                      weeklyMinutes: weeklyGoalMinutes, from: .now)
        targetDateSet = true
    }

    /// Statements to show: 5 from the band the hours point to, 5 from the next, interleaved.
    var canDoStatements: [(text: String, isNextBand: Bool)] {
        let sample = CanDo.placementStatements(for: bandByHours, pack: pack)
        var result: [(text: String, isNextBand: Bool)] = []
        for index in 0..<max(sample.own.count, sample.next.count) {
            if index < sample.own.count { result.append((text: sample.own[index], isNextBand: false)) }
            if index < sample.next.count { result.append((text: sample.next[index], isNextBand: true)) }
        }
        return result
    }

    var placement: Placement.Result {
        let statements = canDoStatements
        let ownYes = statements.filter { !$0.isNextBand && canDoAnswers[$0.text] == true }.count
        let nextYes = statements.filter { $0.isNextBand && canDoAnswers[$0.text] == true }.count
        return Placement.place(hours: trainingHours, ownBandYes: ownYes, nextBandYes: nextYes, statementsPerBand: CanDo.placementSampleSize, levels: pack.levels)
    }

    func apply(to profile: LearnerProfile) {
        let calendar = Calendar.current
        profile.languageCode = languageCode
        profile.displayName = name.trimmingCharacters(in: .whitespaces)
        profile.goal = goal
        profile.targetDate = targetDate
        profile.enabledSources = sources
        profile.baselineInputHours = inputHours
        profile.band = placement.band
        // Starting from zero: the easiest videos and the start of every course.
        let difficulty = startingFromZero ? 0 : dreamingDifficultyLow
        profile.dsDifficulty = difficulty...(difficulty + profile.gradedWindowWidth)
        profile.languageTransferLastTrack = startingFromZero ? 0 : languageTransferLastTrack
        profile.extraEpisodesWatched = startingFromZero ? 0 : extraEpisodesWatched
        profile.duolingoSection = startingFromZero ? 1 : duolingoSection
        profile.duolingoUnit = startingFromZero ? 1 : duolingoUnit
        profile.reminderEnabled = reminderEnabled
        profile.reminderHour = calendar.component(.hour, from: reminderTime)
        profile.reminderMinute = calendar.component(.minute, from: reminderTime)
        profile.weeklyGoalMinutes = weeklyGoalMinutes
        profile.weekStartsOnSunday = weekStartsOnSunday
        if isCustomLanguage {
            profile.customLanguageName = customLanguageName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.customLanguageFlag = customLanguageFlag
            profile.customSources = customSources
            profile.strandBalance = usesOwnBalance ? ownBalance : nil
        }
    }
}
