import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Spherical geometry for guess feedback.
///
/// Distance is the great-circle length on a sphere. Direction is the initial
/// bearing, degrees clockwise from true north. Proximity compares that
/// distance with the farthest two points on Earth can be: half a circumference.
public enum Earth {
    /// IUGG mean radius.
    public static let radiusKilometers = 6371.0088
    /// International statute mile.
    public static let kilometersPerMile = 1.609344

    public static var halfCircumferenceKilometers: Double {
        radiusKilometers * .pi
    }

    public static func miles(fromKilometers kilometers: Double) -> Double {
        kilometers / kilometersPerMile
    }
}

public func greatCircleDistanceKilometers(
    latitude1: Double,
    longitude1: Double,
    latitude2: Double,
    longitude2: Double
) -> Double {
    let phi1 = latitude1 * .pi / 180
    let phi2 = latitude2 * .pi / 180
    let deltaPhi = (latitude2 - latitude1) * .pi / 180
    let deltaLambda = (longitude2 - longitude1) * .pi / 180
    let sinPhi = sin(deltaPhi / 2)
    let sinLambda = sin(deltaLambda / 2)
    let a = sinPhi * sinPhi + cos(phi1) * cos(phi2) * sinLambda * sinLambda
    let clamped = min(1, max(0, a))
    let central = 2 * atan2(sqrt(clamped), sqrt(1 - clamped))
    return Earth.radiusKilometers * central
}

public func initialBearingDegrees(
    latitude1: Double,
    longitude1: Double,
    latitude2: Double,
    longitude2: Double
) -> Double {
    let phi1 = latitude1 * .pi / 180
    let phi2 = latitude2 * .pi / 180
    let deltaLambda = (longitude2 - longitude1) * .pi / 180
    let y = sin(deltaLambda) * cos(phi2)
    let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
    if abs(x) < 1e-12 && abs(y) < 1e-12 {
        return 0
    }
    let degrees = atan2(y, x) * 180 / .pi
    return normalizeDegrees(degrees)
}

public func proximityPercent(distanceKilometers: Double) -> Int {
    let farthest = Earth.halfCircumferenceKilometers
    guard farthest > 0 else { return 0 }
    let ratio = 1 - distanceKilometers / farthest
    let percent = min(100, max(0, ratio * 100))
    return Int(percent.rounded())
}

public func compassArrow(bearingDegrees: Double) -> String {
    let arrows = ["⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️"]
    return arrows[compassOctant(bearingDegrees: bearingDegrees)]
}

public func compassName(bearingDegrees: Double) -> String {
    let names = [
        "north", "northeast", "east", "southeast",
        "south", "southwest", "west", "northwest",
    ]
    return names[compassOctant(bearingDegrees: bearingDegrees)]
}

func compassOctant(bearingDegrees: Double) -> Int {
    let normalized = normalizeDegrees(bearingDegrees)
    return Int((normalized + 22.5) / 45) % 8
}

func normalizeDegrees(_ degrees: Double) -> Double {
    let turns = degrees / 360
    let wrapped = (turns - turns.rounded(.down)) * 360
    return wrapped < 0 ? wrapped + 360 : wrapped
}
