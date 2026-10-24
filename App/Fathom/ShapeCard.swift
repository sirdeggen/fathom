import FathomCore
import SwiftUI

struct RegionOutline: Shape {
    let region: Region

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard region.width > 0, region.height > 0 else { return path }
        let pad = min(rect.width, rect.height) * 0.08
        let available = rect.insetBy(dx: pad, dy: pad)
        let scale = min(
            available.width / CGFloat(region.width),
            available.height / CGFloat(region.height)
        )
        let drawnWidth = CGFloat(region.width) * scale
        let drawnHeight = CGFloat(region.height) * scale
        let originX = available.minX + (available.width - drawnWidth) / 2
        let originY = available.minY + (available.height - drawnHeight) / 2

        for polygon in region.polygons {
            for ring in polygon {
                guard ring.count >= 6 else { continue }
                path.move(to: point(ring[0], ring[1], originX: originX, originY: originY, scale: scale))
                var index = 2
                while index + 1 < ring.count {
                    path.addLine(
                        to: point(ring[index], ring[index + 1], originX: originX, originY: originY, scale: scale)
                    )
                    index += 2
                }
                path.closeSubpath()
            }
        }
        return path
    }

    private func point(
        _ x: Int,
        _ y: Int,
        originX: CGFloat,
        originY: CGFloat,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(x: originX + CGFloat(x) * scale, y: originY + CGFloat(y) * scale)
    }
}

struct ShapeCard: View {
    let region: Region
    let revealedName: String?
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            RegionOutline(region: region)
                .fill(Ink.shape, style: FillStyle(eoFill: true))
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(revealedName.map { "Outline of \($0)" } ?? "Mystery outline")

            if let revealedName {
                VStack(spacing: 4) {
                    Text(revealedName)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(Ink.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .padding(revealedName == nil ? 8 : 16)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(revealedName == nil ? Ink.line : Ink.good, lineWidth: revealedName == nil ? 1 : 2)
        }
    }
}
