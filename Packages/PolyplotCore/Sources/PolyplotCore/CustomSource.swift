import Foundation

/// A source the learner adds themselves (Settings → Sources → Custom sources): a podcast, a textbook, a
/// grammar app. It fills one strand ("study type"), at a length between its own minimum and maximum, and
/// can be switched off without deleting it. Each language has its own. See docs/02-learning-engine.md §2.3.
public struct CustomSource: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var strand: Strand
    public var minMinutes: Int
    public var maxMinutes: Int
    public var isEnabled: Bool

    /// The lengths a custom task can be set to.
    public static let minuteLimits = 1...240

    public init(id: UUID = UUID(), name: String, strand: Strand, minMinutes: Int, maxMinutes: Int, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.strand = strand
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
        self.isEnabled = isEnabled
    }

    /// The kind its tasks are planned and logged as.
    public var kind: TaskKind { TaskKind.custom(for: strand) }

    /// Its range, kept sensible whatever was saved: within `minuteLimits`, and the maximum never below the minimum.
    /// The standard length (for "Keep going") is the middle.
    public var minuteRange: MinuteRange {
        let low = min(max(minMinutes, Self.minuteLimits.lowerBound), Self.minuteLimits.upperBound)
        let high = min(max(maxMinutes, low), Self.minuteLimits.upperBound)
        return MinuteRange(min: low, standard: (low + high + 1) / 2, max: high)
    }

    /// Switched on and named: the planner may use it.
    public var isActive: Bool {
        isEnabled && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
