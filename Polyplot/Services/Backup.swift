import Foundation
import PolyplotCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Manual backup: Settings → Save backup writes one `.polyplot` file; Restore reads one back.
/// The file is this struct as JSON, compressed (LZFSE) and wrapped in a `BackupContainer` (a "POLYPLOT" marker,
/// a format version and a checksum), so it isn't readable or editable as text and a changed file is refused.
/// Plain-JSON backups from before that are no longer accepted.
/// Today's plan isn't included; it's rebuilt from the restored history.
/// Version 2 holds every language being learned: each profile, and a language on every log, writing entry
/// and card. A version 1 file (one profile, no languages) restores as Spanish. The field names for source
/// progress date from when Spanish was the only language and stay as they are.
struct BackupFile: Codable {
    static let currentVersion = 2

    var version: Int
    var exportedAt: Date
    var appVersion: String
    var profile: ProfileData
    var logs: [LogData]
    var writing: [WritingData]
    /// Added after version 1 shipped; optional so older backups still restore.
    var cards: [CardData]?
    /// Version 2: every language's profile (`profile` is the one being learned, kept for older readers).
    var profiles: [ProfileData]?
    /// Version 2: the language being learned when the backup was saved.
    var activeLanguage: String?
    /// The Gemini key and thinking level (Keychain and UserDefaults on the phone). Optional: older backups have none.
    var gemini: GeminiData?
    /// Today's plan in each language (and a plan made ahead for a later day), so restoring on the same day
    /// keeps which cards are done. Added later: older backups have none, and today's plan is rebuilt.
    var plans: [PlanData]?
    /// One-off moments already shown (a freeze that saved the streak, a unit completed…), so a restore or
    /// a new phone doesn't show them again. Added later.
    var momentsSeen: [String]?

    struct GeminiData: Codable {
        var apiKey: String?
        var thinkingLevel: String?
        /// Added later: the Groq key and which checker goes first ("gemini" or "groq").
        var groqAPIKey: String?
        var defaultChecker: String?
    }

    struct ProfileData: Codable {
        var createdAt: Date
        var displayName: String
        var goal: String
        var targetDate: Date?
        var band: String
        var speakingStage: Int
        var weeklyGoalMinutes: Int
        var habitCue: String
        var reminderEnabled: Bool
        var reminderHour: Int
        var reminderMinute: Int
        var travelMode: Bool
        var enabledSources: [String]
        var keepDuolingoInB2: Bool
        var baselineInputHours: Double
        var dsDifficultyLow: Int
        var dsDifficultyHigh: Int
        var languageTransferLastTrack: Int
        var languageTransferRepeatPending: Bool
        var extraEpisodesWatched: Int
        var extraPartsDoneInEpisode: Int
        var duolingoSection: Int
        var duolingoUnit: Int
        // Added after version 1 shipped; optional so older backups still restore.
        var gatesPassed: Int?
        var lastFailedGate: Date?
        var weekStartsOnSunday: Bool?
        var currentContentID: String?
        var alwaysIncludeDuolingo: Bool?
        var speakingStageCap: Int?
        var lessonSchedule: LessonSchedule?
        var pathHistory: PathLayout.PathHistory?
        var strandBalance: StrandBalance?
        /// Added later: Settings → Sources → Custom sources.
        var customSources: [CustomSource]?
        /// Added later: an "Other language"'s name and emoji.
        var customLanguageName: String?
        var customLanguageFlag: String?
        /// Added later: Settings → Writing history.
        var keepsWritingHistory: Bool?
        /// Version 2: the language this profile is for. Missing means Spanish.
        var language: String?
    }

    struct LogData: Codable {
        var date: Date
        var task: String
        var minutes: Int
        var comprehension: Int?
        var rating: String?
        var isBonus: Bool
        var difficultyLow: Int?
        var difficultyHigh: Int?
        var levelWatched: Int?
        /// Version 2. Missing means Spanish.
        var language: String?
        /// Added later, so a restored plan's done cards can still be undone. Missing gives a new ID.
        var id: UUID?
        /// Added later: a custom task's source and its name.
        var customSourceID: UUID?
        var customSourceName: String?
    }

    struct WritingData: Codable {
        var date: Date
        var task: String
        var prompt: String
        var text: String
        // Added after version 1 shipped.
        var rewrite: String?
        var feedback: Data?
        var id: UUID?
        /// Version 2. Missing means Spanish.
        var language: String?
        /// Added later: training hours and level when it was written (Writing history).
        var trainingHours: Double?
        var band: String?
    }

    struct CardData: Codable {
        var createdAt: Date
        var front: String
        var back: String
        var explanation: String
        var origin: String
        var writingID: UUID?
        var due: Date
        var stability: Double
        var difficulty: Double
        var reps: Int
        var lapses: Int
        var state: Int
        var lastReview: Date?
        /// Version 2. Missing means Spanish.
        var language: String?
        /// Added later, so undoing a restored mistake review finds its cards. Missing gives a new ID.
        var id: UUID?
    }

    struct PlanData: Codable {
        var language: String
        var day: Date
        var budgetMinutes: Int
        var band: String
        var tasks: [TaskData]
    }

    /// Every field of a planned task, so a restored card behaves exactly as before (timer, draft, undo).
    struct TaskData: Codable {
        var task: String
        var order: Int
        var minutesPlanned: Int
        var isAnchor: Bool
        var isExtra: Bool
        var draftText: String
        var draftRewrite: String
        var draftFeedback: Data?
        var detail: String
        var prompt: String
        var status: String
        var startedAt: Date?
        var pausedAt: Date?
        var pausedSeconds: Double
        var logID: UUID?
        var splitLogIDs: [UUID]
        var writingID: UUID?
        var progressBefore: Data?
        var duolingoSectionBefore: Int?
        var duolingoUnitBefore: Int?
        var reviewsBefore: Data?
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// The `.polyplot` file: JSON, compressed, in a checksummed container.
    func fileData() throws -> Data {
        let json = try Self.encoder().encode(self)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        return BackupContainer.wrap(compressed)
    }

    /// Reads a `.polyplot` file. Anything else (an old plain-JSON backup, another file) is refused.
    static func read(_ fileData: Data) throws -> BackupFile {
        let payload: Data
        do {
            payload = try BackupContainer.unwrap(fileData)
        } catch BackupContainer.Failure.notABackup {
            throw BackupError.notABackup
        } catch BackupContainer.Failure.newerFormat {
            throw BackupError.newerVersion
        } catch {
            throw BackupError.damaged
        }
        guard let json = try? (payload as NSData).decompressed(using: .lzfse) as Data else { throw BackupError.damaged }
        return try decode(json)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)
        guard file.version <= currentVersion else { throw BackupError.newerVersion }
        return file
    }
}

enum BackupError: LocalizedError {
    case newerVersion
    case unreadable
    case notABackup
    case damaged

    var errorDescription: String? {
        switch self {
        case .newerVersion: "This backup was made by a newer version of Polyplot. Update the app first."
        case .unreadable: "That file couldn't be read. Pick a Polyplot backup (.polyplot)."
        case .notABackup: "That isn't a Polyplot backup. Pick a .polyplot file saved from Settings → Save backup."
        case .damaged: "This backup has been changed or damaged since it was saved, so it can't be restored."
        }
    }
}

extension BackupFile.ProfileData {
    init(_ profile: LearnerProfile) {
        self.init(
            createdAt: profile.createdAt, displayName: profile.displayName, goal: profile.goal,
            targetDate: profile.targetDate, band: profile.currentBandRaw, speakingStage: profile.speakingStageRaw,
            weeklyGoalMinutes: profile.weeklyGoalMinutes, habitCue: profile.habitCue,
            reminderEnabled: profile.reminderEnabled, reminderHour: profile.reminderHour, reminderMinute: profile.reminderMinute,
            travelMode: profile.travelMode, enabledSources: profile.enabledSourcesRaw, keepDuolingoInB2: profile.keepDuolingoInB2,
            baselineInputHours: profile.baselineInputHours, dsDifficultyLow: profile.dsDifficultyLow, dsDifficultyHigh: profile.dsDifficultyHigh,
            languageTransferLastTrack: profile.languageTransferLastTrack, languageTransferRepeatPending: profile.languageTransferRepeatPending,
            extraEpisodesWatched: profile.extraEpisodesWatched, extraPartsDoneInEpisode: profile.extraPartsDoneInEpisode,
            duolingoSection: profile.duolingoSection, duolingoUnit: profile.duolingoUnit,
            gatesPassed: profile.gatesPassed, lastFailedGate: profile.lastFailedGate,
            weekStartsOnSunday: profile.weekStartsOnSunday,
            currentContentID: profile.currentContentID,
            alwaysIncludeDuolingo: profile.alwaysIncludeDuolingo,
            speakingStageCap: profile.speakingStageCap,
            lessonSchedule: profile.lessonScheduleData == nil ? nil : profile.lessonSchedule,
            pathHistory: profile.pathHistoryData == nil ? nil : profile.pathHistory,
            strandBalance: profile.strandBalance,
            customSources: profile.customSources.isEmpty ? nil : profile.customSources,
            customLanguageName: profile.customLanguageName.isEmpty ? nil : profile.customLanguageName,
            customLanguageFlag: profile.customLanguageFlag.isEmpty ? nil : profile.customLanguageFlag,
            keepsWritingHistory: profile.keepsWritingHistory,
            language: profile.languageCode
        )
    }

    func makeProfile() -> LearnerProfile {
        let profile = LearnerProfile()
        profile.languageCode = language ?? LanguagePack.defaultCode
        profile.createdAt = createdAt
        profile.displayName = displayName
        profile.goal = goal
        profile.targetDate = targetDate
        profile.currentBandRaw = band
        profile.speakingStageRaw = speakingStage
        profile.weeklyGoalMinutes = weeklyGoalMinutes
        profile.habitCue = habitCue
        profile.reminderEnabled = reminderEnabled
        profile.reminderHour = reminderHour
        profile.reminderMinute = reminderMinute
        profile.travelMode = travelMode
        profile.enabledSourcesRaw = enabledSources
        profile.keepDuolingoInB2 = keepDuolingoInB2
        profile.baselineInputHours = baselineInputHours
        profile.dsDifficultyLow = dsDifficultyLow
        profile.dsDifficultyHigh = dsDifficultyHigh
        profile.languageTransferLastTrack = languageTransferLastTrack
        profile.languageTransferRepeatPending = languageTransferRepeatPending
        profile.extraEpisodesWatched = extraEpisodesWatched
        profile.extraPartsDoneInEpisode = extraPartsDoneInEpisode
        profile.duolingoSection = duolingoSection
        profile.duolingoUnit = duolingoUnit
        profile.gatesPassed = gatesPassed ?? 0
        profile.lastFailedGate = lastFailedGate
        profile.weekStartsOnSunday = weekStartsOnSunday ?? false
        profile.currentContentID = currentContentID ?? ""
        profile.alwaysIncludeDuolingo = alwaysIncludeDuolingo ?? true
        profile.speakingStageCap = speakingStageCap ?? SpeakingStage.calls.rawValue
        if let lessonSchedule { profile.lessonSchedule = lessonSchedule }
        if let pathHistory { profile.pathHistory = pathHistory }
        profile.strandBalance = strandBalance
        profile.customSources = customSources ?? []
        profile.customLanguageName = customLanguageName ?? ""
        profile.customLanguageFlag = customLanguageFlag ?? ""
        profile.keepsWritingHistory = keepsWritingHistory ?? true
        return profile
    }
}

extension BackupFile.CardData {
    init(_ card: ReviewCard) {
        self.init(createdAt: card.createdAt, front: card.front, back: card.back, explanation: card.explanation, origin: card.origin,
                  writingID: card.writingID, due: card.due, stability: card.stability, difficulty: card.difficulty,
                  reps: card.reps, lapses: card.lapses, state: card.stateRaw, lastReview: card.lastReview,
                  language: card.languageCode, id: card.id)
    }

    func makeCard() -> ReviewCard {
        let card = ReviewCard(front: front, back: back, explanation: explanation, origin: origin)
        card.languageCode = language ?? LanguagePack.defaultCode
        card.createdAt = createdAt
        card.writingID = writingID
        card.due = due
        card.stability = stability
        card.difficulty = difficulty
        card.reps = reps
        card.lapses = lapses
        card.stateRaw = state
        card.lastReview = lastReview
        if let id { card.id = id }
        return card
    }
}

extension BackupFile.LogData {
    init(_ log: ActivityLog) {
        self.init(date: log.date, task: log.taskRaw, minutes: log.minutes, comprehension: log.comprehension,
                  rating: log.rating, isBonus: log.isBonus, difficultyLow: log.difficultyLow, difficultyHigh: log.difficultyHigh,
                  levelWatched: log.levelWatched, language: log.languageCode, id: log.id,
                  customSourceID: log.customSourceID, customSourceName: log.customSourceName)
    }

    func makeLog() -> ActivityLog {
        let log = ActivityLog(date: date, task: .gradedWatch, minutes: minutes)
        log.taskRaw = task
        log.languageCode = language ?? LanguagePack.defaultCode
        log.comprehension = comprehension
        log.rating = rating
        log.isBonus = isBonus
        log.difficultyLow = difficultyLow
        log.difficultyHigh = difficultyHigh
        log.levelWatched = levelWatched
        log.customSourceID = customSourceID
        log.customSourceName = customSourceName
        if let id { log.id = id }
        return log
    }
}

extension BackupFile.PlanData {
    init(_ plan: DayPlanRecord) {
        self.init(language: plan.languageCode, day: plan.day, budgetMinutes: plan.budgetMinutes, band: plan.bandRaw,
                  tasks: plan.sortedTasks.map(BackupFile.TaskData.init))
    }

    /// The plan and its tasks, ready to insert (the tasks are linked to the plan).
    func makePlan() -> (plan: DayPlanRecord, tasks: [PlannedTaskRecord]) {
        let plan = DayPlanRecord(day: day, budgetMinutes: budgetMinutes, band: Band(rawValue: band) ?? .a2_1)
        plan.bandRaw = band
        plan.languageCode = language
        let records = tasks.map { $0.makeTask() }
        records.forEach { $0.plan = plan }
        return (plan, records)
    }
}

extension BackupFile.TaskData {
    init(_ task: PlannedTaskRecord) {
        self.init(task: task.taskRaw, order: task.order, minutesPlanned: task.minutesPlanned, isAnchor: task.isAnchor,
                  isExtra: task.isExtra, draftText: task.draftText, draftRewrite: task.draftRewrite, draftFeedback: task.draftFeedback,
                  detail: task.detailRaw, prompt: task.prompt, status: task.statusRaw, startedAt: task.startedAt,
                  pausedAt: task.pausedAt, pausedSeconds: task.pausedSeconds, logID: task.logID, splitLogIDs: task.splitLogIDs,
                  writingID: task.writingID, progressBefore: task.progressBefore, duolingoSectionBefore: task.duolingoSectionBefore,
                  duolingoUnitBefore: task.duolingoUnitBefore, reviewsBefore: task.reviewsBefore)
    }

    func makeTask() -> PlannedTaskRecord {
        let record = PlannedTaskRecord(restoredOrder: order)
        record.taskRaw = task
        record.minutesPlanned = minutesPlanned
        record.prompt = prompt
        record.isAnchor = isAnchor
        record.isExtra = isExtra
        record.draftText = draftText
        record.draftRewrite = draftRewrite
        record.draftFeedback = draftFeedback
        record.detailRaw = detail
        record.statusRaw = status
        record.startedAt = startedAt
        record.pausedAt = pausedAt
        record.pausedSeconds = pausedSeconds
        record.logID = logID
        record.splitLogIDs = splitLogIDs
        record.writingID = writingID
        record.progressBefore = progressBefore
        record.duolingoSectionBefore = duolingoSectionBefore
        record.duolingoUnitBefore = duolingoUnitBefore
        record.reviewsBefore = reviewsBefore
        return record
    }
}

/// The backup as a document for SwiftUI's file exporter (saving to Files worked on device in M0).
extension UTType {
    /// A Polyplot backup (`.polyplot`), declared in Info.plist (project.yml: UTExportedTypeDeclarations).
    static let polyplotBackup = UTType(exportedAs: "com.rahns.polyplot.backup", conformingTo: .data)

    /// One-time import: backups saved before the app was renamed, so the picker offers them and data can
    /// move to the renamed app. Their type is declared as imported in Info.plist (project.yml:
    /// UTImportedTypeDeclarations), so the picker recognises them whether or not the old app is still
    /// installed. Remove once that's done (docs/04-data-model.md §4.3).
    static let legacyBackup = UTType(importedAs: "com.rahns.rumbo.backup", conformingTo: .data)

    /// Everything the restore picker accepts.
    static let restorableBackups: [UTType] = [.polyplotBackup, .legacyBackup]
        + [UTType(filenameExtension: "rumbo", conformingTo: .data)].compactMap { $0 }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.polyplotBackup]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func defaultFilename(on date: Date = .now) -> String {
        "Polyplot Backup \(date.formatted(.iso8601.year().month().day()))"
    }
}

/// Picks a backup file and hands back its contents. Imports a copy, so no lasting file access is needed.
struct BackupImportPicker: UIViewControllerRepresentable {
    /// Called with the file's data, `nil` if cancelled, or an error if it couldn't be read.
    let onFinish: (Result<Data, Error>?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: UTType.restorableBackups, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Result<Data, Error>?) -> Void

        init(onFinish: @escaping (Result<Data, Error>?) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return onFinish(nil) }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                onFinish(.success(try Data(contentsOf: url)))
            } catch {
                onFinish(.failure(error))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(nil)
        }
    }
}
