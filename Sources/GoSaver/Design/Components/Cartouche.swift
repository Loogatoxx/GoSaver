import SwiftUI

/// Bloc-titre encadré d'un double filet, comme le cartouche d'une carte ancienne
/// (docs/DESIGN_SYSTEM.md §6.1). Un seul par écran, jamais d'icône.
struct Cartouche: View {
    let title: String
    let subtitle: String
    let survey: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(Typo.title)
                .foregroundStyle(Ink.ink)
            Text(subtitle)
                .font(Typo.water)
                .foregroundStyle(Ink.inkFaded)
            GraduatedRule()
                .padding(.vertical, Space.s1)
            Text(survey)
                .font(Typo.figure)
                .foregroundStyle(Ink.inkFaded)
        }
        .padding(Space.s5)
        // L'ombre va sur la feuille seule, sinon SwiftUI l'applique aussi au texte.
        .background(Ink.paperRaised.sheetShadow())
        .overlay(DoubleRule())
    }
}

/// Double filet : trait fort extérieur, trait fin intérieur, 3 pt d'écart.
struct DoubleRule: View {
    var body: some View {
        ZStack {
            Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.ruleStrong)
            Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.hairline)
                .padding(Stroke.ruleStrong + 3)
        }
    }
}

/// Séparateur en forme de règle : filet fin et graduations aux extrémités.
/// Remplace toute barre pleine arrondie.
struct GraduatedRule: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            // Graduations tous les 8 pt sur les 40 premiers et derniers points.
            for x in stride(from: 0.0, through: 40.0, by: 8.0) {
                let tall: CGFloat = x == 0 ? 4 : 2.5
                for px in [x, size.width - x] {
                    path.move(to: CGPoint(x: px, y: y - tall))
                    path.addLine(to: CGPoint(x: px, y: y + tall))
                }
            }
            context.stroke(path, with: .color(Ink.contour), lineWidth: Stroke.hairline)
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}
