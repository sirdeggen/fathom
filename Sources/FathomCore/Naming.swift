import Foundation

/// Fold a place name so typing ignores case, accents, and light punctuation.
///
/// Apostrophes are dropped, so "Côte d'Ivoire" and "cote d’ivoire" share one key.
/// Spaces stay spaces. A leading "the" is dropped, and "St." is treated as "Saint".
public func canonicalName(_ raw: String) -> String {
    var text = raw.lowercased()
    let replacements = [
        ("ø", "o"), ("ł", "l"), ("đ", "d"), ("æ", "ae"), ("œ", "oe"),
        ("ß", "ss"), ("ð", "d"), ("þ", "th"),
    ]
    for (from, to) in replacements {
        text = text.replacingOccurrences(of: from, with: to)
    }
    let decomposed = text.decomposedStringWithCanonicalMapping
    // Apostrophes are part of the spelling ("d'Ivoire"), not word breaks.
    let dropped: Set<Unicode.Scalar> = ["'", "’", "`", "´", "ʻ", "ʼ"]
    var characters: [Character] = []
    var pendingSpace = false
    for scalar in decomposed.unicodeScalars {
        if scalar.properties.generalCategory == .nonspacingMark || dropped.contains(scalar) {
            continue
        }
        if CharacterSet.alphanumerics.contains(scalar) {
            if pendingSpace, !characters.isEmpty {
                characters.append(" ")
            }
            pendingSpace = false
            characters.append(Character(scalar))
        } else if !characters.isEmpty {
            pendingSpace = true
        }
    }
    var words = String(characters).split(separator: " ").map(String.init)
    if words.first == "the" {
        words.removeFirst()
    }
    words = words.map { word in
        word == "st" || word == "ste" ? "saint" : word
    }
    return words.joined(separator: " ")
}

public struct NameIndex: Sendable {
    private struct Entry: Sendable {
        let region: Region
        let keys: [String]
    }

    private let entries: [Entry]

    public init(regions: [Region]) {
        entries = regions.map { region in
            let keys = ([region.name] + region.aliases).map(canonicalName)
            return Entry(region: region, keys: keys)
        }
    }

    /// An exact name or alias, after canonical folding. Ambiguous text does not match.
    public func match(query: String, excluding: Set<String> = []) -> Region? {
        let key = canonicalName(query)
        guard !key.isEmpty else { return nil }
        return entries.first { entry in
            !excluding.contains(entry.region.id) && entry.keys.contains(key)
        }?.region
    }

    /// Valid names for the current mode, best matches first.
    public func suggestions(
        query: String,
        excluding: Set<String> = [],
        limit: Int = 6
    ) -> [Region] {
        let key = canonicalName(query)
        guard !key.isEmpty else { return [] }
        var ranked: [(tier: Int, name: String, region: Region)] = []
        for entry in entries where !excluding.contains(entry.region.id) {
            guard let tier = bestTier(query: key, keys: entry.keys) else { continue }
            ranked.append((tier, entry.region.name, entry.region))
        }
        ranked.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        var seen: Set<String> = []
        var result: [Region] = []
        for item in ranked where seen.insert(item.region.id).inserted {
            result.append(item.region)
            if result.count == limit { break }
        }
        return result
    }
}

private func bestTier(query: String, keys: [String]) -> Int? {
    var best: Int?
    for candidate in keys {
        let tier: Int?
        if candidate == query {
            tier = 0
        } else if candidate.hasPrefix(query) {
            tier = 1
        } else if candidate.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
            tier = 2
        } else if candidate.contains(query) {
            tier = 3
        } else {
            tier = nil
        }
        if let tier, best == nil || tier < best! {
            best = tier
        }
    }
    return best
}
