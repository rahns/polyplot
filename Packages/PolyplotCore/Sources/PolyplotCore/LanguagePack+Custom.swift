import Foundation

extension LanguagePack {
    /// Codes of languages the learner names themselves ("Other language") start with this: a BCP 47
    /// private-use tag, so they can never clash with a real language's code.
    public static let customCodePrefix = "x-"

    /// Whether `code` is a language the learner named themselves.
    public static func isCustom(_ code: String?) -> Bool { code?.hasPrefix(customCodePrefix) == true }

    /// A fresh code for a new "Other language" ("x-3f9a1c2e").
    public static func newCustomCode() -> String {
        customCodePrefix + UUID().uuidString.prefix(8).lowercased()
    }

    /// Whether this pack is a language the learner named themselves.
    public var isCustom: Bool { Self.isCustom(code) }

    /// A language Polyplot has no pack for ("Other language"). It has **no built-in sources**: every task comes
    /// from the learner's own (`CustomSource`), so its plan is made of custom tasks plus the app's own
    /// extras (mistake review, travel missions). Its wording is English, since Polyplot doesn't know the
    /// language's words; its level hours are Spanish's, the best-documented roadmap there is.
    /// See docs/09-multi-language.md §9.10.
    public static func custom(code: String, name: String, flag: String) -> LanguagePack {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = name.isEmpty ? "your language" : name
        return LanguagePack(
            code: code,
            name: shown,
            nativeName: shown,
            flag: flag.isEmpty ? defaultCustomFlag : flag,
            localeIdentifier: "en",
            levels: spanish.levels,
            sources: [:],
            course: nil,
            series: nil,
            graded: nil,
            drill: nil,
            anchors: [:],
            tutor: Tutor(focus: "grammar, agreement, verb forms and tenses, word order, spelling and word choice",
                         languageToolCode: nil, explainInLanguageFrom: nil),
            phrases: Phrasebook.english,
            catalog: CatalogSource(resource: "", remoteURL: "", cacheFile: "content-catalog.\(code).json"),
            wording: ["region": "a place where \(shown) is spoken", "regional": "local",
                      "places": "a place where \(shown) is spoken", "filmOrigin": "a place where \(shown) is spoken"])
    }

    /// The emoji an "Other language" gets until one is chosen.
    public static let defaultCustomFlag = "🌐"

    /// Makes a learner-named language known to `pack(for:)`. The app registers each one from its profile
    /// at launch, after a restore and when one is set up or renamed.
    public static func register(_ pack: LanguagePack) {
        customRegistry.set(pack)
    }

    /// The learner-named languages registered so far.
    public static var registeredCustom: [LanguagePack] { customRegistry.all }

    static let customRegistry = CustomPackRegistry()
}

/// The learner-named languages known this run (`LanguagePack.register`). A class with a lock so the
/// static can be read from any thread.
final class CustomPackRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var packs: [String: LanguagePack] = [:]

    func set(_ pack: LanguagePack) {
        lock.lock()
        defer { lock.unlock() }
        packs[pack.code] = pack
    }

    func pack(for code: String) -> LanguagePack? {
        lock.lock()
        defer { lock.unlock() }
        return packs[code]
    }

    var all: [LanguagePack] {
        lock.lock()
        defer { lock.unlock() }
        return packs.values.sorted { $0.code < $1.code }
    }
}
