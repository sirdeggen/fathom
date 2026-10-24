import SwiftUI

struct AboutView: View {
    let attribution: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("An outline, six guesses, and the distance between them.")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Ink.primary)

                    Text("You see the shape of a US state or a country, filled and centered, with no labels and no map around it. Name it. Each miss tells you how far that guess sits from the answer, which way to look, and how close you came.")
                        .foregroundStyle(Ink.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        AboutRow(title: "Distance", detail: "Great-circle kilometers between the two centers. Switch to miles from the km button.")
                        AboutRow(title: "Direction", detail: "The arrow is the initial compass bearing from your guess toward the answer.")
                        AboutRow(title: "Proximity", detail: "100% is the answer itself. 0% is halfway around the Earth.")
                        AboutRow(title: "Daily", detail: "One outline per mode, the same for everyone on that UTC date. Your guesses are saved on this device.")
                        AboutRow(title: "Practice", detail: "Unlimited shapes. They do not change your streak.")
                    }

                    Text("Shapes are simplified from Natural Earth public-domain maps and drawn as vectors. Distant islands are sometimes left off so the main landmass stays recognizable. Alaska and Hawaii are played as states, and the United States outline is the contiguous states. France is European France, including Corsica.")
                        .foregroundStyle(Ink.primary)

                    Text(attribution)
                        .font(.footnote)
                        .foregroundStyle(Ink.muted)

                    Text("Fathom is an independent game. It is not affiliated with any other geography puzzle.")
                        .font(.footnote)
                        .foregroundStyle(Ink.muted)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Ink.paper)
            .navigationTitle("About")
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

private struct AboutRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.accent)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Ink.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
