import Foundation

public enum PuzzleMode: String, Codable, CaseIterable, Sendable {
    case countries
    case states

    public var title: String {
        switch self {
        case .countries: return "Countries"
        case .states: return "States"
        }
    }

    public var prompt: String {
        switch self {
        case .countries: return "Name the country"
        case .states: return "Name the state"
        }
    }
}

/// Everyone playing on this UTC date gets the same index.
///
/// The hash is FNV-1a 64, not Swift's randomized `Hasher`, so the result does
/// not change between launches or platforms. `count` is the number of outlines
/// in that mode after they have been sorted by id.
public func dailyIndex(mode: String, date: String, count: Int) -> Int {
    precondition(count > 0, "A puzzle needs at least one outline")
    let hash = fnv1a64("\(mode)|\(date)|fathom-v1")
    return Int(hash % UInt64(count))
}

func fnv1a64(_ text: String) -> UInt64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    let prime: UInt64 = 1_099_511_628_211
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }
    return hash
}

public func utcDayString(from date: Date) -> String {
    let parts = utcCalendar.dateComponents([.year, .month, .day], from: date)
    let year = parts.year ?? 1970
    let month = parts.month ?? 1
    let day = parts.day ?? 1
    return String(format: "%04d-%02d-%02d", year, month, day)
}

public func previousUTCDay(_ day: String) -> String? {
    guard let date = parseUTCDay(day),
          let previous = utcCalendar.date(byAdding: .day, value: -1, to: date) else {
        return nil
    }
    return utcDayString(from: previous)
}

public func formatShareDate(_ day: String) -> String {
    let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    let pieces = day.split(separator: "-")
    guard pieces.count == 3,
          let year = Int(pieces[0]),
          let month = Int(pieces[1]),
          let dayNumber = Int(pieces[2]),
          (1...12).contains(month),
          (1...31).contains(dayNumber) else {
        return day
    }
    return "\(months[month - 1]) \(dayNumber), \(year)"
}

func parseUTCDay(_ day: String) -> Date? {
    let pieces = day.split(separator: "-")
    guard pieces.count == 3,
          let year = Int(pieces[0]),
          let month = Int(pieces[1]),
          let dayNumber = Int(pieces[2]) else {
        return nil
    }
    var components = DateComponents()
    components.calendar = utcCalendar
    components.timeZone = utcCalendar.timeZone
    components.year = year
    components.month = month
    components.day = dayNumber
    return components.date
}

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()
