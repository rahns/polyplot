import Foundation
import Testing
@testable import PolyplotCore

/// The learner's own sources (docs/02-learning-engine.md §2.3 "Custom sources").
@Suite struct CustomSourceTests {
    let planner = DayPlanner(calendar: TestCalendar.utc)
    let today = TestCalendar.day(2026, 10, 26)
    let podcast = CustomSource(name: "A podcast", strand: .input, minMinutes: 15, maxMinutes: 25)

    func learner(_ sources: [CustomSource], band: Band = .a2_1) -> LearnerSnapshot {
        var learner = band == .a2_1 ? authorAtStart : LearnerSnapshot(band: band)
        learner.customSources = sources
        return learner
    }

    func plan(_ budget: Int, _ learner: LearnerSnapshot, history: [ActivityRecord] = []) -> DayPlan {
        planner.plan(budget: budget, learner: learner, history: history, today: today)
    }

    /// A week in which the graded video library was watched every day and the podcast `podcastDays` times.
    func history(podcastDays: Int) -> [ActivityRecord] {
        (1...6).map { ActivityRecord(date: TestCalendar.adding(days: -$0, to: today), kind: .gradedWatch, minutes: 20) }
            + (0..<podcastDays).map { ActivityRecord(date: TestCalendar.adding(days: -1 - $0, to: today), kind: .customInput, minutes: 20, customSourceID: podcast.id) }
    }

    @Test func eachStrandHasItsOwnKind() {
        for strand in Strand.allCases {
            #expect(TaskKind.custom(for: strand).strand == strand)
            #expect(TaskKind.custom(for: strand).isCustom)
            #expect(TaskKind.custom(for: strand).source == nil)
        }
        #expect(TaskKind.customInput.countsAsInput)
        #expect(!TaskKind.customStudy.countsAsInput)
    }

    @Test func rangeIsKeptSensible() {
        #expect(CustomSource(name: "A", strand: .input, minMinutes: 10, maxMinutes: 20).minuteRange == MinuteRange(min: 10, standard: 15, max: 20))
        // A maximum below the minimum is raised to it; lengths stay within the limits.
        #expect(CustomSource(name: "A", strand: .input, minMinutes: 30, maxMinutes: 10).minuteRange == MinuteRange(min: 30, standard: 30, max: 30))
        #expect(CustomSource(name: "A", strand: .input, minMinutes: 0, maxMinutes: 999).minuteRange.min == CustomSource.minuteLimits.lowerBound)
        #expect(CustomSource(name: "A", strand: .input, minMinutes: 0, maxMinutes: 999).minuteRange.max == CustomSource.minuteLimits.upperBound)
    }

    @Test func aNewSourceIsPlannedWithinItsRange() {
        let plan = plan(45, learner([podcast]))
        let task = plan.tasks.first { $0.detail == .custom(podcast.id) }
        #expect(task?.kind == .customInput)
        #expect(task.map { (15...25).contains($0.minutes) } == true, "\(String(describing: task?.minutes))")
        #expect(plan.totalMinutes <= 45)
    }

    @Test func switchedOffOrUnnamedSourcesAreNeverPlanned() {
        var off = podcast
        off.isEnabled = false
        let unnamed = CustomSource(name: "  ", strand: .input, minMinutes: 10, maxMinutes: 20)
        let learner = learner([off, unnamed])
        #expect(!learner.isEligible(.customInput))
        for budget in DayPlanner.budgetChoices {
            #expect(plan(budget, learner).tasks.allSatisfy { !$0.kind.isCustom }, "\(budget) min")
        }
        #expect(planner.extraTasks(learner: learner, history: [], today: today, excluding: []).allSatisfy { !$0.kind.isCustom })
    }

    /// Today's first listening card.
    func firstInput(_ sources: [CustomSource], podcastDays: Int) -> PlannedTask? {
        var learner = learner(sources)
        learner.balance = StrandBalance(shares: [.input: 1])
        // No learner series, whose weekly anchor would go first.
        learner.enabledSources.remove(.learnerSeries)
        return plan(30, learner, history: history(podcastDays: podcastDays)).tasks.first { $0.kind.strand == .input }
    }

    @Test func customAndBuiltInTakeTurnsOverAWeek() {
        // Used less than the built-in listening this week: it goes first.
        #expect(firstInput([podcast], podcastDays: 2)?.detail == .custom(podcast.id))
        // Caught up with it: the built-in task goes first.
        #expect(firstInput([podcast], podcastDays: 6)?.kind == .gradedWatch)
    }

    @Test func dueAnchorsStillGoFirst() {
        // The learner series' weekly episode is due: it keeps its place ahead of a custom source.
        var learner = learner([podcast])
        learner.balance = StrandBalance(shares: [.input: 1])
        #expect(plan(30, learner).tasks.first { $0.kind.strand == .input }?.kind == .seriesIntensive)
    }

    @Test func theLeastUsedCustomSourceGoesFirst() {
        let show = CustomSource(name: "A show", strand: .input, minMinutes: 15, maxMinutes: 25)
        #expect(firstInput([podcast, show], podcastDays: 1)?.detail == .custom(show.id))
        #expect(firstInput([show, podcast], podcastDays: 0)?.detail == .custom(show.id), "a tie keeps the learner's order")
    }

    @Test func aStrandWithOnlyCustomSourcesIsStillPlanned() {
        var learner = learner([CustomSource(name: "Textbook", strand: .languageFocused, minMinutes: 10, maxMinutes: 20)])
        // Every built-in study source off.
        learner.enabledSources = [.gradedVideo, .writing, .exchange, .suggestedContent]
        #expect(learner.canPlan(.languageFocused))
        let plan = plan(45, learner)
        #expect(plan.kinds.contains(.customStudy))
        #expect(plan.tasks.filter { $0.kind.strand == .languageFocused }.allSatisfy { $0.kind == .customStudy })
    }

    @Test func leftoverTimeStaysWithinTheSourcesRange() {
        // Listening only: whatever is left over goes to input cards, but never past a source's maximum.
        var learner = learner([podcast])
        learner.balance = StrandBalance(shares: [.input: 1])
        for budget in DayPlanner.budgetChoices {
            for task in plan(budget, learner).tasks where task.kind.isCustom {
                #expect(task.minutes >= 15 && task.minutes <= 25, "\(budget) min: \(task.minutes)")
            }
        }
    }

    @Test func aShortDayCanBeACustomSource() {
        var learner = learner([CustomSource(name: "Flashcards", strand: .languageFocused, minMinutes: 5, maxMinutes: 10)])
        learner.alwaysIncludeDrillApp = false
        learner.enabledSources = [.gradedVideo, .writing, .exchange, .suggestedContent]
        learner.balance = StrandBalance(shares: [.languageFocused: 1])
        let plan = plan(10, learner)
        #expect(plan.kinds == [.customStudy])
        #expect(plan.totalMinutes == 10)
    }

    @Test func keepGoingOffersEachCustomSourceNotPlanned() {
        let show = CustomSource(name: "A show", strand: .input, minMinutes: 20, maxMinutes: 40)
        let learner = learner([podcast, show])
        let extras = planner.extraTasks(learner: learner, history: [], today: today, excluding: [], excludingCustom: [podcast.id])
        #expect(!extras.contains { $0.detail == .custom(podcast.id) })
        #expect(extras.first { $0.detail == .custom(show.id) }?.minutes == 30)
    }
}
