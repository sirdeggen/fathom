import FathomCore
import SwiftUI

struct GuessList: View {
    let lines: [GuessLine]
    let useMiles: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            if lines.isEmpty {
                Text("Type a name. A miss still points the way.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                ForEach(lines) { line in
                    GuessRow(line: line, useMiles: useMiles, reduceMotion: reduceMotion)
                }
            }
        }
    }
}

private struct GuessRow: View {
    let line: GuessLine
    let useMiles: Bool
    let reduceMotion: Bool
    @State private var aimed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(line.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if line.correct {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Ink.good)
                        .accessibilityLabel("Correct")
                } else {
                    Image(systemName: "location.north.fill")
                        .font(.title3)
                        .foregroundStyle(Ink.accent)
                        .rotationEffect(.degrees(aimed ? line.bearing : (reduceMotion ? line.bearing : 0)))
                        .onAppear { aimed = true }
                        .animation(reduceMotion ? nil : .spring(duration: 0.55), value: aimed)
                        .accessibilityLabel(compassName(bearingDegrees: line.bearing))
                }
            }

            if line.correct {
                Text("Right on the outline.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.good)
            } else {
                HStack {
                    Text(DistanceText.string(
                        kilometers: line.distanceKilometers,
                        useMiles: useMiles,
                        exact: false
                    ))
                    Text("·")
                    Text("\(line.proximity)%")
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Ink.muted)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.line)
                        Capsule()
                            .fill(Ink.accent)
                            .frame(width: proxy.size.width * CGFloat(line.proximity) / 100)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(line.correct ? Ink.good.opacity(0.45) : Ink.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GuessEntry: View {
    @Binding var query: String
    let prompt: String
    let suggestions: [Region]
    let onSubmit: (String) -> Void
    let onPick: (Region) -> Void
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { region in
                            Button {
                                onPick(region)
                            } label: {
                                HStack {
                                    Text(region.name)
                                        .foregroundStyle(Ink.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.footnote)
                                        .foregroundStyle(Ink.muted)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if region.id != suggestions.last?.id {
                                Divider().overlay(Ink.line)
                            }
                        }
                    }
                }
                .frame(maxHeight: 264)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ink.muted)
                TextField(prompt, text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { onSubmit(query) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
        .background(.ultraThinMaterial)
    }
}
