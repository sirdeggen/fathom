import FathomCore
import SwiftUI

struct StatsView: View {
    let controller: GameController
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PuzzleMode = .countries

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Mode", selection: $mode) {
                        Text("States").tag(PuzzleMode.states)
                        Text("Countries").tag(PuzzleMode.countries)
                    }
                    .pickerStyle(.segmented)

                    let stats = controller.stats(for: mode)
                    if stats.played == 0 {
                        ContentUnavailableView(
                            "No daily record yet",
                            systemImage: "chart.bar",
                            description: Text("Finish a daily outline and it lands here. Practice rounds stay off the books.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatTile(title: "Played", value: "\(stats.played)")
                            StatTile(title: "Win %", value: stats.winPercent.map(String.init) ?? "—")
                            StatTile(title: "Streak", value: "\(stats.currentStreak)")
                            StatTile(title: "Best", value: "\(stats.maxStreak)")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Guesses")
                                .font(.headline)
                                .foregroundStyle(Ink.primary)
                            let peak = max(stats.guessCounts.max() ?? 0, stats.failures, 1)
                            ForEach(0..<Round.guessLimit, id: \.self) { index in
                                DistributionRow(
                                    label: "\(index + 1)",
                                    count: stats.guessCounts[index],
                                    peak: peak
                                )
                            }
                            DistributionRow(label: "—", count: stats.failures, peak: peak)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper)
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Ink.muted)
            Text(value)
                .font(.system(.title, design: .serif).weight(.medium))
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DistributionRow: View {
    let label: String
    let count: Int
    let peak: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Ink.muted)
                .frame(width: 20, alignment: .trailing)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.line)
                    Capsule()
                        .fill(Ink.accent)
                        .frame(width: proxy.size.width * CGFloat(count) / CGFloat(peak))
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Ink.primary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "—" ? "Missed" : "Solved in \(label)") , \(count)")
    }
}
