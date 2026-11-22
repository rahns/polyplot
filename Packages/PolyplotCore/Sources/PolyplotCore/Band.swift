/// The eight internal levels Polyplot plans for, from a complete beginner (A1.1, zero hours) to B2.2.
/// See docs/02-learning-engine.md §2.1 and docs/10-beginners.md for A1.
/// The hours each one starts at and its friendly name depend on the language (`LanguagePack.levels`, `levelName`).
public enum Band: String, CaseIterable, Codable, Sendable, Comparable {
    /// Complete beginners: from the first word.
    case a1_1 = "A1.1"
    case a1_2 = "A1.2"
    case a2_1 = "A2.1"
    case a2_2 = "A2.2"
    case b1_1 = "B1.1"
    case b1_2 = "B1.2"
    case b2_1 = "B2.1"
    case b2_2 = "B2.2"

    /// The share of training time that's listening at every band. Level hours are listening milestones ÷ this.
    public static let listeningShare = 0.55

    /// Training hours equivalent to `hours` of listening, for listening done before Polyplot (e.g. Dreaming Spanish's counter).
    public static func trainingHours(fromListening hours: Double) -> Double {
        hours / listeningShare
    }

    /// Settings → Level & training hours: the listening before Polyplot that gives `target` training hours in all,
    /// on top of `loggedHours` logged in Polyplot. Logged practice can't be taken away, so a target below it
    /// gives no listening before Polyplot (total = the logged hours).
    public static func listeningBaseline(forTrainingHours target: Double, loggedHours: Double) -> Double {
        max(0, target - loggedHours) * listeningShare
    }

    /// Share of weekly minutes per strand (R1). Each row sums to 1; listening is 55% throughout, except at A1.1,
    /// where a complete beginner studies more than they listen (45%).
    public var strandTargets: [Strand: Double] {
        switch self {
        // Beginners lean on structured study (an audio course, Duolingo) while there's little they can understand
        // yet, and speak and write very little: Nation's language-focused strand is at its largest here. No fluency
        // practice yet: there's nothing to make faster until there's something known well. At A1.1 no separate
        // speaking or writing either: Language Transfer and Duolingo already have the learner answering out loud.
        // A1.1 is also the one level with more study than listening: at zero, a few hundred words and the basic
        // patterns make every minute of listening worth more. Not further than 55%: there's only so much course.
        case .a1_1: [.input: 0.45, .output: 0, .languageFocused: 0.55, .fluency: 0]
        case .a1_2: [.input: 0.55, .output: 0.10, .languageFocused: 0.35, .fluency: 0]
        case .a2_1: [.input: 0.55, .output: 0.13, .languageFocused: 0.24, .fluency: 0.08]
        case .a2_2: [.input: 0.55, .output: 0.15, .languageFocused: 0.22, .fluency: 0.08]
        case .b1_1: [.input: 0.55, .output: 0.18, .languageFocused: 0.18, .fluency: 0.09]
        case .b1_2: [.input: 0.55, .output: 0.20, .languageFocused: 0.15, .fluency: 0.10]
        case .b2_1: [.input: 0.55, .output: 0.23, .languageFocused: 0.10, .fluency: 0.12]
        case .b2_2: [.input: 0.55, .output: 0.25, .languageFocused: 0.08, .fluency: 0.12]
        }
    }

    public static func < (lhs: Band, rhs: Band) -> Bool {
        let order = Band.allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Nation's four strands.
public enum Strand: String, CaseIterable, Codable, Sendable {
    case input
    case output
    case languageFocused
    case fluency
}

extension Band {
    /// The first level, from this one up, whose plan includes `strand` (A1.2 for speaking & writing, A2.1 for
    /// fluency), or nil if none does. For "Starts at A2.1" on a strand that's at 0% for now.
    public func firstBand(including strand: Strand) -> Band? {
        Band.allCases.first { $0 >= self && ($0.strandTargets[strand] ?? 0) > 0 }
    }
}


extension Band {
    /// What a learner at this level can roughly do, in a line, for estimating where you are (onboarding's
    /// "Not sure?" list). Language-neutral, like the can-do statements.
    public var summary: String {
        switch self {
        case .a1_1: "Just starting: a few words and phrases at most."
        case .a1_2: "Greetings, numbers and simple questions about yourself. You catch single words when people speak slowly."
        case .a2_1: "Short, simple conversations about familiar things, with help. You follow slow, clear speech, especially with pictures."
        case .a2_2: "Shopping, directions and small talk. You get the gist of easy videos made for learners."
        case .b1_1: "You follow most of a conversation on familiar topics and can talk about your day, plans and experiences."
        case .b1_2: "Learner shows are easy and native ones are possible with effort. You can explain what you think and why."
        case .b2_1: "You follow most native speech on familiar topics, and hold your own in a discussion."
        case .b2_2: "You understand most native content, fast speech included, and speak fluently on most topics."
        }
    }
}

extension LevelScale {
    /// Roughly how many hours of listening before Polyplot put someone in the middle of `band`: halfway to the
    /// next level's training hours (a little past the start at the last level), converted to listening at
    /// the plan's listening share and rounded to 10. For onboarding's "Not sure?" list.
    public func typicalListeningHours(for band: Band) -> Int {
        let start = threshold(band)
        let end = band.next.map(threshold) ?? start * 1.2
        let listening = (start + end) / 2 * Band.listeningShare
        return Int((listening / 10).rounded()) * 10
    }
}
