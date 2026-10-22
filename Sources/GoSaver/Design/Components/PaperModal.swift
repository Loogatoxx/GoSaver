import SwiftUI

/// Feuille modale de la charte : voile de papier sur la fenêtre, feuille à double filet au centre.
/// Un clic sur le voile appelle `onDismiss` (s'il est fourni).
struct PaperModal<Content: View>: View {
    var width: CGFloat = 480
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            // Voile de papier : la carte reste devinable derrière.
            Ink.paper.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { onDismiss?() }
            VStack(alignment: .leading, spacing: Space.s4) { content }
                .padding(Space.s6)
                .frame(width: width, alignment: .leading)
                .background(Ink.paperRaised.sheetShadow(lifted: true))
                .overlay(DoubleRule())
        }
    }
}
