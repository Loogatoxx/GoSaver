import SwiftUI

/// Bouton « Sceau » : l'unique action principale d'un écran (docs/DESIGN_SYSTEM.md §6.2).
/// Au survol la feuille se soulève ; à l'appui elle s'enfonce comme un tampon encreur.
struct SealButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SealBody(configuration: configuration)
    }

    private struct SealBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .regionStyle()
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, Space.s5)
                .padding(.vertical, Space.s3)
                .background(
                    Rectangle()
                        .fill(Ink.vermilion)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .sheetShadow(lifted: hovering && !pressed)
                )
                .opacity(enabled ? 1 : 0.45)
                .offset(y: pressed ? 1 : (hovering ? -1 : 0))
                .animation(Motion.quick, value: pressed)
                .animation(Motion.quick, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Bouton « Tracé » : action secondaire, contour d'encre.
struct TraceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.label)
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Ink.ink, lineWidth: Stroke.rule))
            .background(configuration.isPressed ? Ink.paperSunken : .clear)
    }
}
