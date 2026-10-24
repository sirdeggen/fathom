import FathomCore
import Foundation
import Observation

enum PlayStyle: String, CaseIterable, Identifiable {
    case daily
    case practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .practice: return "Practice"
        }
    }
}

enum PulseKind: Equatable {
    case none
    case wrong
    case correct
    case lost
}

struct GuessLine: Identifiable, Equatable {
    let id: String
    let name: String
    let distanceKilometers: Double
    let bearing: Double
    let proximity: Int
    let correct: Bool
}

@MainActor
@Observable
final class GameController {
    let catalog: RegionCatalog

    var mode: PuzzleMode = .countries
    var style: PlayStyle = .daily
    var useMiles = false {
        didSet {
            if persist, oldValue != useMiles { save() }
        }
    }
    private var persist = false

    private(set) var today: String
    private(set) var pulse = 0
    private(set) var pulseKind: PulseKind = .none

    private let defaults: UserDefaults
    private let defaultsKey = "fathom.save.v1"
    private var countryStats = ModeStats()
    private var stateStats = ModeStats()
    private var countriesDaily: DailyProgress?
    private var statesDaily: DailyProgress?
    private var countryPractice: Round
    private var statePractice: Round
    private let countryNames: NameIndex
    private let stateNames: NameIndex

    init(catalog: RegionCatalog, now: Date = Date(), defaults: UserDefaults = .standard) {
        self.catalog = catalog
        self.defaults = defaults
        self.today = utcDayString(from: now)
        self.countryNames = NameIndex(regions: catalog.countries)
        self.stateNames = NameIndex(regions: catalog.states)
        self.countryPractice = Self.makePractice(in: catalog, mode: .countries, avoiding: nil)
        self.statePractice = Self.makePractice(in: catalog, mode: .states, avoiding: nil)
        load()
        reconcileAll()
        persist = true
        save()
    }

    var activeRound: Round {
        switch style {
        case .daily:
            let answer = dailyAnswerID(mode: mode, day: today)
            let saved = dailyProgress(for: mode)
            let guesses = saved?.day == today ? saved?.guessIDs ?? [] : []
            return Round(answerID: answer, guessIDs: guesses)
        case .practice:
            return practiceRound(for: mode)
        }
    }

    var answer: Region? {
        catalog.region(id: activeRound.answerID, mode: mode)
    }

    var guessLines: [GuessLine] {
        guard let answer else { return [] }
        return activeRound.guessIDs.compactMap { id in
            guard let guess = catalog.region(id: id, mode: mode) else { return nil }
            let distance = greatCircleDistanceKilometers(
                latitude1: guess.latitude,
                longitude1: guess.longitude,
                latitude2: answer.latitude,
                longitude2: answer.longitude
            )
            let correct = guess.id == answer.id
            return GuessLine(
                id: guess.id,
                name: guess.name,
                distanceKilometers: distance,
                bearing: correct
                    ? 0
                    : initialBearingDegrees(
                        latitude1: guess.latitude,
                        longitude1: guess.longitude,
                        latitude2: answer.latitude,
                        longitude2: answer.longitude
                    ),
                proximity: correct ? 100 : proximityPercent(distanceKilometers: distance),
                correct: correct
            )
        }
    }

    func stats(for mode: PuzzleMode) -> ModeStats {
        switch mode {
        case .countries: return countryStats
        case .states: return stateStats
        }
    }

    func suggestions(for query: String) -> [Region] {
        guard !activeRound.isOver else { return [] }
        return names(for: mode).suggestions(
            query: query,
            excluding: Set(activeRound.guessIDs)
        )
    }

    func submit(query: String) {
        guard !activeRound.isOver else { return }
        let excluding = Set(activeRound.guessIDs)
        let index = names(for: mode)
        if let exact = index.match(query: query, excluding: excluding) {
            guess(exact.id)
            return
        }
        let options = index.suggestions(query: query, excluding: excluding)
        if options.count == 1 {
            guess(options[0].id)
        }
    }

    func guess(_ id: String) {
        guard catalog.region(id: id, mode: mode) != nil else { return }
        var round = activeRound
        guard round.addGuess(id) else { return }
        if style == .daily {
            var progress = dailyProgress(for: mode) ?? DailyProgress(day: today, guessIDs: [], recorded: false)
            if progress.day != today {
                progress = DailyProgress(day: today, guessIDs: [], recorded: false)
            }
            progress.guessIDs = round.guessIDs
            if round.isOver, !progress.recorded {
                record(solved: round.isSolved, guesses: round.guessIDs.count)
                progress.recorded = true
            }
            setDaily(progress, for: mode)
        } else {
            setPractice(round, for: mode)
        }
        if round.isSolved {
            pulseKind = .correct
        } else if round.isOver {
            pulseKind = .lost
        } else {
            pulseKind = .wrong
        }
        pulse += 1
        save()
    }

    func newPracticeShape() {
        let previous = practiceRound(for: mode).answerID
        setPractice(Self.makePractice(in: catalog, mode: mode, avoiding: previous), for: mode)
    }

    func refreshClock(now: Date = Date()) {
        let day = utcDayString(from: now)
        guard day != today else { return }
        today = day
        reconcileAll()
        save()
    }

    func shareMessage() -> String {
        let title = style == .practice ? "\(mode.title) · Practice" : mode.title
        let guesses = guessLines.map { line in
            ShareGuess(
                arrow: line.correct ? nil : compassArrow(bearingDegrees: line.bearing),
                proximity: line.proximity,
                correct: line.correct
            )
        }
        return shareText(modeTitle: title, day: today, guesses: guesses)
    }

    private func names(for mode: PuzzleMode) -> NameIndex {
        switch mode {
        case .countries: return countryNames
        case .states: return stateNames
        }
    }

    private func dailyAnswerID(mode: PuzzleMode, day: String) -> String {
        let regions = catalog.regions(for: mode)
        guard !regions.isEmpty else { return "" }
        let index = dailyIndex(mode: mode.rawValue, date: day, count: regions.count)
        return regions[index].id
    }

    private static func makePractice(
        in catalog: RegionCatalog,
        mode: PuzzleMode,
        avoiding: String?
    ) -> Round {
        let regions = catalog.regions(for: mode)
        guard !regions.isEmpty else { return Round(answerID: "") }
        var index = Int.random(in: 0..<regions.count)
        if regions.count > 1, regions[index].id == avoiding {
            index = (index + 1) % regions.count
        }
        return Round(answerID: regions[index].id)
    }

    private func record(solved: Bool, guesses: Int) {
        switch mode {
        case .countries:
            countryStats.record(solved: solved, guesses: guesses, day: today)
        case .states:
            stateStats.record(solved: solved, guesses: guesses, day: today)
        }
    }

    private func reconcileAll() {
        if let countriesDaily {
            let answer = dailyAnswerID(mode: .countries, day: countriesDaily.day)
            let result = reconcileDaily(
                progress: countriesDaily,
                stats: countryStats,
                today: today,
                answerID: answer
            )
            self.countriesDaily = result.progress
            countryStats = sanitize(result.stats)
        }
        if let statesDaily {
            let answer = dailyAnswerID(mode: .states, day: statesDaily.day)
            let result = reconcileDaily(
                progress: statesDaily,
                stats: stateStats,
                today: today,
                answerID: answer
            )
            self.statesDaily = result.progress
            stateStats = sanitize(result.stats)
        }
    }

    private func dailyProgress(for mode: PuzzleMode) -> DailyProgress? {
        switch mode {
        case .countries: return countriesDaily
        case .states: return statesDaily
        }
    }

    private func setDaily(_ progress: DailyProgress, for mode: PuzzleMode) {
        switch mode {
        case .countries: countriesDaily = progress
        case .states: statesDaily = progress
        }
    }

    private func practiceRound(for mode: PuzzleMode) -> Round {
        switch mode {
        case .countries: return countryPractice
        case .states: return statePractice
        }
    }

    private func setPractice(_ round: Round, for mode: PuzzleMode) {
        switch mode {
        case .countries: countryPractice = round
        case .states: statePractice = round
        }
    }

    private func sanitize(_ stats: ModeStats) -> ModeStats {
        var stats = stats
        if stats.guessCounts.count != Round.guessLimit {
            stats.guessCounts = Array(repeating: 0, count: Round.guessLimit)
        }
        return stats
    }

    private struct Snapshot: Codable {
        var useMiles: Bool
        var countryStats: ModeStats
        var stateStats: ModeStats
        var countriesDaily: DailyProgress?
        var statesDaily: DailyProgress?
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        useMiles = snapshot.useMiles
        countryStats = sanitize(snapshot.countryStats)
        stateStats = sanitize(snapshot.stateStats)
        countriesDaily = snapshot.countriesDaily
        statesDaily = snapshot.statesDaily
    }

    private func save() {
        let snapshot = Snapshot(
            useMiles: useMiles,
            countryStats: countryStats,
            stateStats: stateStats,
            countriesDaily: countriesDaily,
            statesDaily: statesDaily
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
