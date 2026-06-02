import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - BodyMapView
// Anatomy heat map showing front + back body figures.
// Each muscle group is colored by training recency:
//   red    = trained today
//   orange = 1–2 days ago
//   yellow = 3–5 days ago
//   grey   = 6+ days ago
//   clear  = no record in last 30 days
// ════════════════════════════════════════════════════════════════════════════

struct BodyMapView: View {
    /// Maps MuscleGroup.rawValue → most-recent training date
    let muscleLastTrained: [String: Date]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 40) {
                figureColumn(isFront: true, label: "Front")
                figureColumn(isFront: false, label: "Back")
            }
            legend
        }
    }

    // MARK: - Figure column

    private func figureColumn(isFront: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let s = Scale(size)
                drawSilhouette(&ctx, s)
                if isFront { drawFront(&ctx, s) } else { drawBack(&ctx, s) }
            }
            .frame(width: 100, height: 210)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: - Silhouette (same for front & back)

    private func drawSilhouette(_ ctx: inout GraphicsContext, _ s: Scale) {
        let c = Color.white.opacity(0.16)
        // Head
        ctx.fill(Path(ellipseIn: s.r(38, 2, 24, 24)), with: .color(c))
        // Neck
        ctx.fill(Path(roundedRect: s.r(44, 26, 12, 10), cornerRadius: s.cr(3)), with: .color(c))
        // Shoulders bar
        ctx.fill(Path(roundedRect: s.r(16, 34, 68, 14), cornerRadius: s.cr(7)), with: .color(c))
        // Torso
        ctx.fill(Path(roundedRect: s.r(27, 46, 46, 76), cornerRadius: s.cr(10)), with: .color(c))
        // Left arm
        ctx.fill(Path(roundedRect: s.r(8, 34, 19, 72), cornerRadius: s.cr(7)), with: .color(c))
        // Right arm
        ctx.fill(Path(roundedRect: s.r(73, 34, 19, 72), cornerRadius: s.cr(7)), with: .color(c))
        // Left leg
        ctx.fill(Path(roundedRect: s.r(27, 120, 21, 82), cornerRadius: s.cr(8)), with: .color(c))
        // Right leg
        ctx.fill(Path(roundedRect: s.r(52, 120, 21, 82), cornerRadius: s.cr(8)), with: .color(c))
    }

    // MARK: - Front muscles

    private func drawFront(_ ctx: inout GraphicsContext, _ s: Scale) {
        // Chest
        if let c = color("chest") {
            ctx.fill(Path(roundedRect: s.r(29, 48, 42, 28), cornerRadius: s.cr(6)), with: .color(c))
        }
        // Core / Abs
        if let c = color("core") {
            ctx.fill(Path(roundedRect: s.r(31, 78, 38, 42), cornerRadius: s.cr(6)), with: .color(c))
        }
        // Shoulders (front — outer deltoids)
        if let c = color("shoulders") {
            ctx.fill(Path(roundedRect: s.r(16, 34, 19, 14), cornerRadius: s.cr(5)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(65, 34, 19, 14), cornerRadius: s.cr(5)), with: .color(c))
        }
        // Arms (biceps)
        if let c = color("arms") {
            ctx.fill(Path(roundedRect: s.r(8, 48, 19, 58), cornerRadius: s.cr(6)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(73, 48, 19, 58), cornerRadius: s.cr(6)), with: .color(c))
        }
        // Legs (quads)
        if let c = color("legs") {
            ctx.fill(Path(roundedRect: s.r(27, 122, 21, 42), cornerRadius: s.cr(7)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(52, 122, 21, 42), cornerRadius: s.cr(7)), with: .color(c))
        }
        // Full body — highlight all front regions
        if let c = color("fullBody") {
            for rect in [
                s.r(29, 48, 42, 28), s.r(31, 78, 38, 42),
                s.r(16, 34, 19, 14), s.r(65, 34, 19, 14),
                s.r(8, 48, 19, 58),  s.r(73, 48, 19, 58),
                s.r(27, 122, 21, 42), s.r(52, 122, 21, 42)
            ] {
                ctx.fill(Path(roundedRect: rect, cornerRadius: s.cr(6)), with: .color(c))
            }
        }
    }

    // MARK: - Back muscles

    private func drawBack(_ ctx: inout GraphicsContext, _ s: Scale) {
        // Upper back (traps + lats)
        if let c = color("back") {
            ctx.fill(Path(roundedRect: s.r(29, 48, 42, 30), cornerRadius: s.cr(6)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(31, 80, 38, 22), cornerRadius: s.cr(5)), with: .color(c))
        }
        // Core (lower back)
        if let c = color("core") {
            ctx.fill(Path(roundedRect: s.r(33, 84, 34, 20), cornerRadius: s.cr(5)), with: .color(c))
        }
        // Shoulders (rear deltoids)
        if let c = color("shoulders") {
            ctx.fill(Path(roundedRect: s.r(16, 34, 19, 14), cornerRadius: s.cr(5)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(65, 34, 19, 14), cornerRadius: s.cr(5)), with: .color(c))
        }
        // Arms (triceps)
        if let c = color("arms") {
            ctx.fill(Path(roundedRect: s.r(8, 48, 19, 58), cornerRadius: s.cr(6)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(73, 48, 19, 58), cornerRadius: s.cr(6)), with: .color(c))
        }
        // Legs (glutes + hamstrings + calves)
        if let c = color("legs") {
            // Glutes (bottom of torso / top of legs)
            ctx.fill(Path(roundedRect: s.r(27, 108, 46, 16), cornerRadius: s.cr(7)), with: .color(c))
            // Hamstrings
            ctx.fill(Path(roundedRect: s.r(27, 122, 21, 40), cornerRadius: s.cr(7)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(52, 122, 21, 40), cornerRadius: s.cr(7)), with: .color(c))
            // Calves
            ctx.fill(Path(roundedRect: s.r(29, 164, 17, 34), cornerRadius: s.cr(6)), with: .color(c))
            ctx.fill(Path(roundedRect: s.r(54, 164, 17, 34), cornerRadius: s.cr(6)), with: .color(c))
        }
        // Full body
        if let c = color("fullBody") {
            for rect in [
                s.r(29, 48, 42, 30), s.r(31, 80, 38, 22),
                s.r(16, 34, 19, 14), s.r(65, 34, 19, 14),
                s.r(8, 48, 19, 58),  s.r(73, 48, 19, 58),
                s.r(27, 108, 46, 16),
                s.r(27, 122, 21, 40), s.r(52, 122, 21, 40),
                s.r(29, 164, 17, 34), s.r(54, 164, 17, 34)
            ] {
                ctx.fill(Path(roundedRect: rect, cornerRadius: s.cr(6)), with: .color(c))
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.red.opacity(0.80), "Today")
            legendDot(.orange.opacity(0.65), "1–2 days")
            legendDot(.yellow.opacity(0.60), "3–5 days")
            legendDot(.gray.opacity(0.40), "6+ days")
        }
        .font(.caption2)
        .foregroundStyle(Color.arkoTextDim)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Colour helper

    private func color(_ muscle: String) -> Color? {
        guard let last = muscleLastTrained[muscle] else { return nil }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 99
        switch days {
        case 0:     return .red.opacity(0.80)
        case 1...2: return .orange.opacity(0.65)
        case 3...5: return .yellow.opacity(0.60)
        default:    return .gray.opacity(0.35)
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Scale helper
// Maps canvas coordinates (100 × 210 design space) → actual view pixels.
// ════════════════════════════════════════════════════════════════════════════

private struct Scale {
    let factor: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(_ size: CGSize, designW: CGFloat = 100, designH: CGFloat = 210) {
        let f = min(size.width / designW, size.height / designH)
        factor = f
        ox = (size.width  - designW * f) / 2
        oy = (size.height - designH * f) / 2
    }

    /// Scale a design-space CGRect to canvas coordinates.
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * factor + ox, y: y * factor + oy,
               width: w * factor, height: h * factor)
    }

    /// Scale a corner radius.
    func cr(_ r: CGFloat) -> CGFloat { r * factor }
}

// MARK: - Preview

struct BodyMapView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.arkoBg.ignoresSafeArea()
            BodyMapView(muscleLastTrained: [
                "chest":     Date(),
                "shoulders": Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                "arms":      Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
                "legs":      Calendar.current.date(byAdding: .day, value: -4, to: Date())!,
                "back":      Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            ])
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
