import FathomCore
import SwiftUI
import UIKit

struct GameScreen: View {
    @Bindable var controller: GameController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var showStats = false
    @State private var showAbout = false
    @State private var confirmNewShape = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 16) {
                    if let answer = controller.answer {
                        ShapeCard(
                            region: answer,
                            revealedName: controller.activeRound.isOver ? answer.name : nil,
                            message: outcomeMessage
                        )
                        .id(answer.id)
                    }
                    progress
                    GuessList(lines: controller.guessLines, useMiles: controller.useMiles)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Ink.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                .background(Ink.paper.ignoresSafeArea(edges: .bottom))
        }
        .sheet(isPresented: $showStats) {
            StatsView(controller: controller)
        }
        .sheet(isPresented: $showAbout) {
            AboutView(attribution: controller.catalog.attribution)
        }
        .confirmationDialog(
            "Discard this outline?",
            isPresented: $confirmNewShape,
            titleVisibility: .visible
        ) {
            Button("Discard guesses", role: .destructive) {
                controller.newPracticeShape()
                query = ""
            }
            Button("Keep guessing", role: .cancel) {}
        } message: {
            Text("The guesses on this practice outline will be cleared.")
        }
        .onChange(of: controller.pulse) { _, _ in
            playHaptic(controller.pulseKind)
        }
        .onChange(of: controller.mode) { _, _ in query = "" }
        .onChange(of: controller.style) { _, _ in query = "" }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refreshClock() }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: controller.answer?.id)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: controller.activeRound.guessIDs)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fathom")
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .foregroundStyle(Ink.primary)
                Spacer()
                Button {
                    controller.useMiles.toggle()
                } label: {
                    Text(controller.useMiles ? "mi" : "km")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 36, minHeight: 32)
                }
                .accessibilityLabel(controller.useMiles ? "Distances in miles" : "Distances in kilometers")
                .accessibilityHint("Switches between kilometers and miles")

                if controller.style == .practice {
                    Button(action: requestNewShape) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .frame(minWidth: 36, minHeight: 32)
                    }
                    .accessibilityLabel("New shape")
                }

                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.bar")
                        .font(.title3)
                        .frame(minWidth: 36, minHeight: 32)
                }
                .accessibilityLabel("Record")

                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .frame(minWidth: 36, minHeight: 32)
                }
                .accessibilityLabel("About")
            }
            .foregroundStyle(Ink.primary)
            .buttonStyle(.plain)

            Picker("Mode", selection: $controller.mode) {
                Text("States").tag(PuzzleMode.states)
                Text("Countries").tag(PuzzleMode.countries)
            }
            .pickerStyle(.segmented)

            Picker("Puzzle", selection: $controller.style) {
                Text("Daily").tag(PlayStyle.daily)
                Text("Practice").tag(PlayStyle.practice)
            }
            .pickerStyle(.segmented)

            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(Ink.muted)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<Round.guessLimit, id: \.self) { index in
                Circle()
                    .fill(dotColor(index))
                    .overlay {
                        Circle().stroke(Ink.muted.opacity(0.35), lineWidth: 1)
                    }
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(controller.activeRound.guessIDs.count) of \(Round.guessLimit) guesses")
    }

    private var bottomBar: some View {
        Group {
            if controller.activeRound.isOver {
                VStack(spacing: 10) {
                    if controller.style == .daily {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Next outline in \(countdownUntilNextUTCDay(from: context.date)) UTC")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Ink.muted)
                        }
                    }
                    HStack(spacing: 10) {
                        ShareLink(item: controller.shareMessage()) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Ink.accent)
                        if controller.style == .practice {
                            Button(action: requestNewShape) {
                                Text("New shape")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Ink.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            } else {
                GuessEntry(
                    query: $query,
                    prompt: controller.mode.prompt,
                    suggestions: controller.suggestions(for: query),
                    onSubmit: submit,
                    onPick: { region in
                        controller.guess(region.id)
                        query = ""
                        searchFocused = false
                    },
                    focused: $searchFocused
                )
            }
        }
    }

    private var statusLine: String {
        switch controller.style {
        case .daily:
            return "\(formatShareDate(controller.today)) · same outline worldwide · UTC"
        case .practice:
            return "A new outline whenever you want one"
        }
    }

    private var outcomeMessage: String? {
        let round = controller.activeRound
        guard round.isOver else { return nil }
        if round.isSolved {
            return round.guessIDs.count == 1 ? "First try." : "Named in \(round.guessIDs.count)."
        }
        return "The outline was this one."
    }

    private func dotColor(_ index: Int) -> Color {
        let round = controller.activeRound
        guard index < round.guessIDs.count else { return .clear }
        if round.isSolved, index == round.guessIDs.count - 1 {
            return Ink.good
        }
        return Ink.accent
    }

    private func submit(_ text: String) {
        let before = controller.activeRound.guessIDs.count
        controller.submit(query: text)
        if controller.activeRound.guessIDs.count > before {
            query = ""
            searchFocused = false
        }
    }

    private func playHaptic(_ kind: PulseKind) {
        switch kind {
        case .wrong:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .correct:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .lost:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .none:
            break
        }
    }

    private func requestNewShape() {
        let round = controller.activeRound
        if round.guessIDs.isEmpty || round.isOver {
            controller.newPracticeShape()
            query = ""
        } else {
            confirmNewShape = true
        }
    }
}
