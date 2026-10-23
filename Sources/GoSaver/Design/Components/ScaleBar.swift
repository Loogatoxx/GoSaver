import SwiftUI

/// Échelle graduée cartographique (docs/DESIGN_SYSTEM.md §6.3).
/// Remplace jauge et barre de progression : cases alternées encre/papier pour
/// l'occupé, hachures vermillon pour le récupérable, lavis de mer pour le libre.
struct ScaleBar: View {
    /// Toutes les valeurs en octets.
    let capacity: Int64
    let used: Int64
    var reclaimable: Int64 = 0

    private let barHeight: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: barHeight + 14)
            HStack {
                Text(Bytes.format(used)).foregroundStyle(Ink.ink)
                Text("occupés").font(Typo.label).foregroundStyle(Ink.inkFaded)
                Spacer()
                Text(Bytes.format(capacity - used)).foregroundStyle(Ink.sea)
                Text(Words.freeSea).font(Typo.water).foregroundStyle(Ink.sea)
            }
            .font(Typo.figure)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disque : \(Bytes.format(used)) occupés sur \(Bytes.format(capacity)), \(Bytes.format(capacity - used)) libres")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard capacity > 0 else { return }
        let top: CGFloat = 12
        let width = size.width
        let x = { (bytes: Int64) in CGFloat(Double(bytes) / Double(capacity)) * width }
        let usedEnd = x(used)
        let reclaimStart = x(max(0, used - reclaimable))

        // Mer libre : lavis.
        context.fill(Path(CGRect(x: usedEnd, y: top, width: width - usedEnd, height: barHeight)),
                     with: .color(Ink.seaWash))

        // Occupé : cases alternées tous les 10 Go, comme une échelle de carte.
        let step = x(10_000_000_000)
        var cx: CGFloat = 0
        var dark = true
        while cx < reclaimStart {
            let w = min(step, reclaimStart - cx)
            context.fill(Path(CGRect(x: cx, y: top, width: w, height: barHeight)),
                         with: .color(dark ? Ink.ink : Ink.paperRaised))
            cx += step
            dark.toggle()
        }

        // Récupérable : hachures obliques vermillon.
        if reclaimable > 0 {
            let rect = CGRect(x: reclaimStart, y: top, width: usedEnd - reclaimStart, height: barHeight)
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                var hatch = Path()
                for hx in stride(from: rect.minX - barHeight, through: rect.maxX, by: 3) {
                    hatch.move(to: CGPoint(x: hx, y: rect.maxY))
                    hatch.addLine(to: CGPoint(x: hx + barHeight, y: rect.minY))
                }
                layer.stroke(hatch, with: .color(Ink.vermilion), lineWidth: 1)
            }
        }

        // Cadre et graduations.
        context.stroke(Path(CGRect(x: 0, y: top, width: width, height: barHeight)),
                       with: .color(Ink.ink), lineWidth: Stroke.rule)
        var ticks = Path()
        for gb in stride(from: 0, through: Int(capacity / 1_000_000_000), by: 10) {
            let tx = x(Int64(gb) * 1_000_000_000)
            let major = gb % 50 == 0
            ticks.move(to: CGPoint(x: tx, y: top))
            ticks.addLine(to: CGPoint(x: tx, y: top - (major ? 6 : 3)))
            if major {
                // La première graduation s'aligne sur le bord, sinon le « 0 » serait coupé à moitié.
                context.draw(Text("\(gb)").font(Typo.label).foregroundStyle(Ink.inkFaded),
                             at: CGPoint(x: tx, y: 0), anchor: gb == 0 ? .topLeading : .top)
            }
        }
        context.stroke(ticks, with: .color(Ink.ink), lineWidth: Stroke.hairline)
    }
}

/// Formatage des tailles comme le Finder : base 10, « Go ».
enum Bytes {
    static func format(_ bytes: Int64) -> String {
        let raw = bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
        // Typographie française : espace insécable entre le nombre et l'unité,
        // que le formateur omet ou remplace selon la police.
        guard let unitStart = raw.firstIndex(where: { $0.isLetter }) else { return raw }
        let number = raw[..<unitStart].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\u{00A0}\u{202F}")))
        return number + "\u{00A0}" + raw[unitStart...]
    }
}
