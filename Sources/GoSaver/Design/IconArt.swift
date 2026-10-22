import SwiftUI
import GoSaverCore

/// L'icône de GoSaver : une île gravée vue du ciel, ses courbes de niveau, ses lignes d'eau,
/// et le jalon vermillon planté au sommet — la même marque que sur la carte quand on choisit un lieu.
/// Dessinée en code (comme la carte), puis exportée en .icns par scripts/make-icon.sh.
struct IconArt: View {
    /// Toujours en encres « Papier » : une icône ne change pas avec le thème.
    private let paper = Color(nsColor: NSColor(hex: 0xF1E9D8))
    private let paperRaised = Color(nsColor: NSColor(hex: 0xF8F2E6))
    private let ink = Color(nsColor: NSColor(hex: 0x1E1912))
    private let contour = Color(nsColor: NSColor(hex: 0x9C7A52))
    private let sea = Color(nsColor: NSColor(hex: 0x2E5A6E))
    private let seaWash = Color(nsColor: NSColor(hex: 0xC9D6D3))
    private let vermilion = Color(nsColor: NSColor(hex: 0xA63412))

    var body: some View {
        Canvas { context, size in
            let s = size.width / 1024
            // Gabarit des icônes macOS : carré arrondi de 824 px centré dans 1024.
            let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            let tileShape = RoundedRectangle(cornerRadius: 185 * s, style: .continuous).path(in: tile)

            // Ombre portée courte, comme une feuille posée.
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 14 * s, x: 0, y: 10 * s))
                layer.fill(tileShape, with: .color(paper))
            }
            let frameInner = RoundedRectangle(cornerRadius: 136 * s, style: .continuous)
                .path(in: tile.insetBy(dx: 50 * s, dy: 50 * s))
            context.drawLayer { layer in
                layer.clip(to: tileShape)
                layer.fill(tileShape, with: .color(seaWash))
                // Tout ce qui suit reste à l'intérieur du cadre de carte.
                layer.clip(to: frameInner)

                let center = CGPoint(x: 500 * s, y: 548 * s)
                let radius = 250 * s

                // Lignes d'eau autour de la côte, de plus en plus espacées vers le large.
                for (i, grow) in [1.10, 1.23, 1.40].enumerated() {
                    layer.stroke(island(center: center, radius: radius * grow),
                                 with: .color(sea.opacity(0.7 - Double(i) * 0.18)), lineWidth: 5 * s)
                }

                // La terre, puis trois courbes de niveau qui se resserrent vers le sommet (décentré).
                layer.fill(island(center: center, radius: radius), with: .color(paperRaised))
                let peak = CGPoint(x: center.x + 70 * s, y: center.y - 70 * s)
                for (i, k) in [0.70, 0.46, 0.24].enumerated() {
                    let c = CGPoint(x: center.x + (peak.x - center.x) * (1 - k), y: center.y + (peak.y - center.y) * (1 - k))
                    layer.stroke(island(center: c, radius: radius * k),
                                 with: .color(contour), lineWidth: (i == 1 ? 8 : 5) * s)
                }
                // La côte, à l'encre.
                layer.stroke(island(center: center, radius: radius), with: .color(ink), lineWidth: 12 * s)

                // Le jalon : tige d'encre et fanion vermillon qui flotte.
                let base = CGPoint(x: peak.x, y: peak.y + 6 * s)
                var pole = Path()
                pole.move(to: base)
                pole.addLine(to: CGPoint(x: base.x, y: base.y - 215 * s))
                layer.stroke(pole, with: .color(ink), style: StrokeStyle(lineWidth: 13 * s, lineCap: .round))
                // Fanion triangulaire, bord libre légèrement ondulé par le vent.
                var flag = Path()
                let top = CGPoint(x: base.x + 6 * s, y: base.y - 210 * s)
                flag.move(to: top)
                flag.addQuadCurve(to: CGPoint(x: top.x + 150 * s, y: top.y + 46 * s),
                                  control: CGPoint(x: top.x + 80 * s, y: top.y + 6 * s))
                flag.addQuadCurve(to: CGPoint(x: top.x, y: top.y + 92 * s),
                                  control: CGPoint(x: top.x + 70 * s, y: top.y + 78 * s))
                flag.closeSubpath()
                layer.fill(flag, with: .color(vermilion))
                // Pied du jalon : petite croix d'arpenteur.
                var cross = Path()
                cross.move(to: CGPoint(x: base.x - 22 * s, y: base.y)); cross.addLine(to: CGPoint(x: base.x + 22 * s, y: base.y))
                layer.stroke(cross, with: .color(ink), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
            }
            // Cadre de carte : double filet intérieur.
            let outer = RoundedRectangle(cornerRadius: 150 * s, style: .continuous)
                .path(in: tile.insetBy(dx: 34 * s, dy: 34 * s))
            context.stroke(outer, with: .color(ink), lineWidth: 9 * s)
            context.stroke(frameInner, with: .color(ink), lineWidth: 3 * s)
        }
    }

    /// Contour d'île organique : un cercle dont le rayon ondule selon un bruit déterministe.
    private func island(center: CGPoint, radius: CGFloat) -> Path {
        let noise = Noise(seed: 0x60_5A_7E)
        var path = Path()
        let steps = 240
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            // Grandes ondulations (caps et baies) + un léger détail de côte.
            let broad = noise.fractal(cos(a) * 0.9 + 3, sin(a) * 0.9 + 7, octaves: 2)
            let detail = noise.value(cos(a) * 4 + 11, sin(a) * 4 + 5)
            let bay = -0.16 * exp(-pow((a - 3.6) * 2.2, 2))   // une baie au sud-ouest
            let r = radius * CGFloat(1 + 0.30 * broad + 0.035 * detail + bay)
            let p = CGPoint(x: center.x + r * CGFloat(cos(a)) * 1.06, y: center.y + r * CGFloat(sin(a)) * 0.9)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}
