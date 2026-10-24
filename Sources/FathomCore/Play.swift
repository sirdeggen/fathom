import Foundation

public struct Round: Equatable, Sendable {
    public static let guessLimit = 6

    public let answerID: String
    public private(set) var guessIDs: [String]
    public let limit: Int

    public init(answerID: String, guessIDs: [String] = [], limit: Int = Round.guessLimit) {
        self.answerID = answerID
        self.guessIDs = guessIDs
        self.limit = limit
    }

    public var isSolved: Bool {
        guessIDs.contains(answerID)
    }

    public var isOver: Bool {
        isSolved || guessIDs.count >= limit
    }

    @discardableResult
    public mutating func addGuess(_ id: String) -> Bool {
        guard !isOver, !guessIDs.contains(id), !id.isEmpty else { return false }
        guessIDs.append(id)
        return true
    }
}

public struct ModeStats: Codable, Equatable, Sendable {
    public var played: Int
    public var wins: Int
    public var currentStreak: Int
    public var maxStreak: Int
    /// Wins by guess count. Index 0 is a first-try win.
    public var guessCounts: [Int]
    public var failures: Int
    public var lastWinDay: String?

    public init(
        played: Int = 0,
        wins: Int = 0,
        currentStreak: Int = 0,
        maxStreak: Int = 0,
        guessCounts: [Int] = Array(repeating: 0, count: Round.guessLimit),
        failures: Int = 0,
        lastWinDay: String? = nil
    ) {
        self.played = played
        self.wins = wins
        self.currentStreak = currentStreak
        self.maxStreak = maxStreak
        self.guessCounts = guessCounts.count == Round.guessLimit
            ? guessCounts
            : Array(repeating: 0, count: Round.guessLimit)
        self.failures = failures
        self.lastWinDay = lastWinDay
    }

    public var winPercent: Int? {
        guard played > 0 else { return nil }
        return Int((Double(wins) / Double(played) * 100).rounded())
    }

    public mutating func record(solved: Bool, guesses: Int, day: String) {
        played += 1
        if solved {
            wins += 1
            let index = min(Round.guessLimit, max(1, guesses)) - 1
            guessCounts[index] += 1
            if let lastWinDay, lastWinDay == previousUTCDay(day) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
            maxStreak = max(maxStreak, currentStreak)
            self.lastWinDay = day
        } else {
            failures += 1
            currentStreak = 0
        }
    }
}

public struct DailyProgress: Codable, Equatable, Sendable {
    public var day: String
    public var guessIDs: [String]
    public var recorded: Bool

    public init(day: String, guessIDs: [String], recorded: Bool) {
        self.day = day
        self.guessIDs = guessIDs
        self.recorded = recorded
    }
}

/// Apply a saved daily round to the stats at most once, then drop it if the day has passed.
public func reconcileDaily(
    progress: DailyProgress?,
    stats: ModeStats,
    today: String,
    answerID: String
) -> (progress: DailyProgress?, stats: ModeStats) {
    guard var progress else { return (nil, stats) }
    var stats = stats
    let round = Round(answerID: answerID, guessIDs: progress.guessIDs)
    if round.isOver, !progress.recorded {
        stats.record(solved: round.isSolved, guesses: progress.guessIDs.count, day: progress.day)
        progress.recorded = true
    }
    if progress.day != today {
        return (nil, stats)
    }
    return (progress, stats)
}

public struct ShareGuess: Equatable, Sendable {
    public var arrow: String?
    public var proximity: Int
    public var correct: Bool

    public init(arrow: String?, proximity: Int, correct: Bool) {
        self.arrow = arrow
        self.proximity = proximity
        self.correct = correct
    }
}

public func shareText(
    modeTitle: String,
    day: String,
    guesses: [ShareGuess],
    limit: Int = Round.guessLimit
) -> String {
    let solved = guesses.contains(where: \.correct)
    let score = solved ? "\(guesses.count)/\(limit)" : "✕/\(limit)"
    var lines = [
        "Fathom · \(modeTitle)",
        "\(formatShareDate(day)) · \(score)",
    ]
    for guess in guesses {
        if guess.correct {
            lines.append("🎯")
        } else if let arrow = guess.arrow {
            lines.append("\(arrow) \(guess.proximity)%")
        }
    }
    return lines.joined(separator: "\n")
}
