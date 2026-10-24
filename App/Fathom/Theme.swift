import FathomCore
import SwiftUI
import UIKit

enum Ink {
    static let paper = adaptive(light: 0xF6F3EC, dark: 0x12110F)
    static let card = adaptive(light: 0xFFFDF8, dark: 0x1C1A17)
    static let shape = adaptive(light: 0x1A2E2A, dark: 0xE7DCCB)
    static let accent = adaptive(light: 0xC45D26, dark: 0xE08A4F)
    static let good = adaptive(light: 0x1F7A4D, dark: 0x7DCEA0)
    static let line = adaptive(light: 0xE3DCD0, dark: 0x2E2A26)
    static let muted = adaptive(light: 0x6F675E, dark: 0xA39B90)
    static let primary = adaptive(light: 0x1C1916, dark: 0xF4EFE6)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum DistanceText {
    static func string(kilometers: Double, useMiles: Bool, exact: Bool) -> String {
        let value = useMiles ? Earth.miles(fromKilometers: kilometers) : kilometers
        let rounded = Int(value.rounded())
        let unit = useMiles ? "mi" : "km"
        if !exact, rounded < 1 {
            return "< 1 \(unit)"
        }
        return "\(grouped(rounded)) \(unit)"
    }

    private static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

func countdownUntilNextUTCDay(from date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let start = calendar.startOfDay(for: date)
    let next = calendar.date(byAdding: .day, value: 1, to: start) ?? date
    let seconds = max(0, Int(next.timeIntervalSince(date)))
    return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
}
