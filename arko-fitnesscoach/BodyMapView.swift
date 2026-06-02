import SwiftUI

// ════════════════════════════════════════════════════════════════════════════
// MARK: - BodyMapView
// Anatomy heat map — front + back human figure.
// Uses ellipses and bezier paths for a more organic, gym-app look.
// Color = training recency: red(today) → orange(1-2d) → yellow(3-5d) → grey(6+d)
// ════════════════════════════════════════════════════════════════════════════

struct BodyMapView: View {
    let muscleLastTrained: [String: Date]
    /// Regions to highlight dimly as secondary (e.g. assisting muscles).
    var secondary: Set<String> = []

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 32) {
                figureColumn(isFront: true,  label: "Front")
                figureColumn(isFront: false, label: "Back")
            }
            legend
        }
    }

    // MARK: - Figure

    private func figureColumn(isFront: Bool, label: String) -> some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let s = Scale(size)
                drawSilhouette(&ctx, s: s)
                if isFront { drawFront(&ctx, s: s) }
                else        { drawBack(&ctx, s: s)  }
            }
            .frame(width: 110, height: 230)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.arkoTextDim)
        }
    }

    // MARK: - Silhouette (organic shapes)

    private func drawSilhouette(_ ctx: inout GraphicsContext, s: Scale) {
        let base = Color.white.opacity(0.14)

        // Head
        ctx.fill(Path(ellipseIn: s.r(38, 1, 24, 26)), with: .color(base))
        // Neck
        ctx.fill(Path(roundedRect: s.r(45, 27, 10, 9),  cornerRadius: s.cr(4)), with: .color(base))
        // Shoulders (wider, rounded)
        ctx.fill(Path(roundedRect: s.r(14, 34, 72, 16), cornerRadius: s.cr(8)), with: .color(base))
        // Torso — tapers slightly at waist
        ctx.fill(torsoPah(s: s), with: .color(base))
        // Left arm
        ctx.fill(armPath(side: .left, s: s),  with: .color(base))
        // Right arm
        ctx.fill(armPath(side: .right, s: s), with: .color(base))
        // Hips
        ctx.fill(Path(roundedRect: s.r(24, 118, 52, 16), cornerRadius: s.cr(8)), with: .color(base))
        // Left leg
        ctx.fill(legPath(side: .left,  s: s), with: .color(base))
        // Right leg
        ctx.fill(legPath(side: .right, s: s), with: .color(base))
    }

    // Torso with slight waist taper
    private func torsoPah(s: Scale) -> Path {
        var p = Path()
        let tl = s.pt(26, 48), tr = s.pt(74, 48)
        let wl = s.pt(29, 86), wr = s.pt(71, 86)
        let bl = s.pt(26, 120), br = s.pt(74, 120)
        p.move(to: tl)
        p.addLine(to: tr)
        p.addQuadCurve(to: wr, control: s.pt(76, 70))
        p.addLine(to: br)
        p.addLine(to: bl)
        p.addLine(to: wl)
        p.addQuadCurve(to: tl, control: s.pt(24, 70))
        p.closeSubpath()
        return p
    }

    private enum Side { case left, right }

    // Arm with slight taper
    private func armPath(side: Side, s: Scale) -> Path {
        let (x1, x2): (CGFloat, CGFloat) = side == .left ? (10, 24) : (76, 90)
        var p = Path()
        p.move(to: s.pt(x1, 34))
        p.addLine(to: s.pt(x2, 34))
        p.addQuadCurve(to: s.pt(x2-2, 108), control: s.pt(x2+2, 72))
        p.addLine(to: s.pt(x1+2, 108))
        p.addQuadCurve(to: s.pt(x1, 34), control: s.pt(x1-2, 72))
        p.closeSubpath()
        return p
    }

    // Leg
    private func legPath(side: Side, s: Scale) -> Path {
        let x: CGFloat = side == .left ? 24 : 52
        var p = Path()
        p.move(to: s.pt(x, 132))
        p.addLine(to: s.pt(x+24, 132))
        p.addQuadCurve(to: s.pt(x+22, 220), control: s.pt(x+26, 178))
        p.addLine(to: s.pt(x+2,  220))
        p.addQuadCurve(to: s.pt(x, 132), control: s.pt(x-2, 178))
        p.closeSubpath()
        return p
    }

    // MARK: - Muscle colours (front)

    private func drawFront(_ ctx: inout GraphicsContext, s: Scale) {
        // Chest — two pec ovals
        if let c = muscleColor("chest") {
            ctx.fill(Path(ellipseIn: s.r(29, 48, 18, 22)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(53, 48, 18, 22)), with: .color(c))
        }
        // Abs — 3 pairs of oblongs
        if let c = muscleColor("core") {
            for row in 0..<3 {
                let y: CGFloat = 76 + CGFloat(row) * 14
                ctx.fill(Path(roundedRect: s.r(31, y, 14, 11), cornerRadius: s.cr(4)), with: .color(c))
                ctx.fill(Path(roundedRect: s.r(55, y, 14, 11), cornerRadius: s.cr(4)), with: .color(c))
            }
        }
        // Shoulders (front delts)
        if let c = muscleColor("shoulders") {
            ctx.fill(Path(ellipseIn: s.r(14, 34, 18, 16)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(68, 34, 18, 16)), with: .color(c))
        }
        // Arms (biceps)
        if let c = muscleColor("arms") {
            ctx.fill(Path(ellipseIn: s.r(10, 46, 14, 30)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(76, 46, 14, 30)), with: .color(c))
            // Forearm
            ctx.fill(Path(ellipseIn: s.r(11, 80, 12, 26)), with: .color(c.opacity(0.7)))
            ctx.fill(Path(ellipseIn: s.r(77, 80, 12, 26)), with: .color(c.opacity(0.7)))
        }
        // Quads
        if let c = muscleColor("legs") {
            ctx.fill(Path(ellipseIn: s.r(25, 134, 22, 38)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(53, 134, 22, 38)), with: .color(c))
            // Calves (front, tibialis)
            ctx.fill(Path(ellipseIn: s.r(27, 178, 16, 28)), with: .color(c.opacity(0.7)))
            ctx.fill(Path(ellipseIn: s.r(57, 178, 16, 28)), with: .color(c.opacity(0.7)))
        }
        // Full body
        if let c = muscleColor("fullBody") {
            for r in [s.r(29,48,18,22), s.r(53,48,18,22),
                      s.r(31,76,14,11), s.r(55,76,14,11),
                      s.r(14,34,18,16), s.r(68,34,18,16),
                      s.r(10,46,14,30), s.r(76,46,14,30),
                      s.r(25,134,22,38),s.r(53,134,22,38)] {
                ctx.fill(Path(ellipseIn: r), with: .color(c))
            }
        }
    }

    // MARK: - Muscle colours (back)

    private func drawBack(_ ctx: inout GraphicsContext, s: Scale) {
        // Traps
        if let c = muscleColor("back") {
            ctx.fill(Path(ellipseIn: s.r(34, 35, 32, 14)), with: .color(c))
        }
        // Lats
        if let c = muscleColor("back") {
            ctx.fill(Path(ellipseIn: s.r(26, 52, 20, 40)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(54, 52, 20, 40)), with: .color(c))
        }
        // Lower back (erectors)
        if let c = muscleColor("back") ?? muscleColor("core") {
            ctx.fill(Path(ellipseIn: s.r(36, 92, 12, 24)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(52, 92, 12, 24)), with: .color(c))
        }
        // Shoulders (rear delts)
        if let c = muscleColor("shoulders") {
            ctx.fill(Path(ellipseIn: s.r(14, 34, 18, 16)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(68, 34, 18, 16)), with: .color(c))
        }
        // Triceps
        if let c = muscleColor("arms") {
            ctx.fill(Path(ellipseIn: s.r(10, 46, 14, 32)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(76, 46, 14, 32)), with: .color(c))
        }
        // Glutes
        if let c = muscleColor("legs") {
            ctx.fill(Path(ellipseIn: s.r(26, 120, 22, 18)), with: .color(c))
            ctx.fill(Path(ellipseIn: s.r(52, 120, 22, 18)), with: .color(c))
        }
        // Hamstrings
        if let c = muscleColor("legs") {
            ctx.fill(Path(ellipseIn: s.r(25, 138, 22, 36)), with: .color(c.opacity(0.85)))
            ctx.fill(Path(ellipseIn: s.r(53, 138, 22, 36)), with: .color(c.opacity(0.85)))
        }
        // Calves
        if let c = muscleColor("legs") {
            ctx.fill(Path(ellipseIn: s.r(27, 180, 16, 26)), with: .color(c.opacity(0.7)))
            ctx.fill(Path(ellipseIn: s.r(57, 180, 16, 26)), with: .color(c.opacity(0.7)))
        }
        // Full body
        if let c = muscleColor("fullBody") {
            for r in [s.r(34,35,32,14), s.r(26,52,20,40), s.r(54,52,20,40),
                      s.r(14,34,18,16), s.r(68,34,18,16),
                      s.r(10,46,14,32), s.r(76,46,14,32),
                      s.r(26,120,22,18),s.r(52,120,22,18),
                      s.r(25,138,22,36),s.r(53,138,22,36)] {
                ctx.fill(Path(ellipseIn: r), with: .color(c))
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(.red.opacity(0.85),    "Today")
            legendItem(.orange.opacity(0.7),  "1–2 days")
            legendItem(.yellow.opacity(0.65), "3–5 days")
            legendItem(.gray.opacity(0.4),    "6+ days")
        }
        .font(.caption2)
        .foregroundStyle(Color.arkoTextDim)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Color helper

    private func muscleColor(_ muscle: String) -> Color? {
        if let last = muscleLastTrained[muscle] {
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 99
            switch days {
            case 0:     return .red.opacity(0.85)
            case 1...2: return .orange.opacity(0.70)
            case 3...5: return .yellow.opacity(0.65)
            default:    return .gray.opacity(0.35)
            }
        }
        // Secondary muscle — dim highlight
        if secondary.contains(muscle) { return .orange.opacity(0.35) }
        return nil
    }
}

// ════════════════════════════════════════════════════════════════════════════
// MARK: - Scale helper
// ════════════════════════════════════════════════════════════════════════════

private struct Scale {
    let factor: CGFloat
    let ox: CGFloat
    let oy: CGFloat

    init(_ size: CGSize, designW: CGFloat = 100, designH: CGFloat = 230) {
        let f = min(size.width / designW, size.height / designH)
        factor = f
        ox = (size.width  - designW * f) / 2
        oy = (size.height - designH * f) / 2
    }

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * factor + ox, y: y * factor + oy,
               width: w * factor,  height: h * factor)
    }

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * factor + ox, y: y * factor + oy)
    }

    func cr(_ r: CGFloat) -> CGFloat { r * factor }
}

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
