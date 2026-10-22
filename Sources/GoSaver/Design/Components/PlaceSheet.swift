import SwiftUI
import AppKit
import GoSaverCore

/// Fiche d'un lieu sélectionné (docs/DESIGN_SYSTEM.md §6.5) : une feuille posée
/// sur la carte, coin supérieur droit corné. Données d'abord, métaphore ensuite.
struct PlaceSheet: View {
    let landmark: AtlasModel.Landmark
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("\(landmark.terrain.name) · \(landmark.terrain.meaning)")
                .regionStyle()
                .foregroundStyle(Ink.inkFaded)
            Text(landmark.title)
                .font(Typo.title)
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(Bytes.format(landmark.bytes)).font(Typo.figureLarge).foregroundStyle(Ink.ink)
                Text(fileCountText).font(Typo.label).foregroundStyle(Ink.inkFaded)
            }
            if landmark.terrain.regenerates {
                Text("Se reforme seul si on l’assèche.")
                    .font(Typo.water).foregroundStyle(Ink.sea)
            }

            GraduatedRule()

            if !landmark.largestFiles.isEmpty {
                Text("Plus gros fichiers").regionStyle().foregroundStyle(Ink.inkFaded)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(landmark.largestFiles, id: \.url) { file in
                        HStack(spacing: Space.s2) {
                            Text(file.url.lastPathComponent)
                                .font(Typo.body).foregroundStyle(Ink.ink)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: Space.s2)
                            Text(Bytes.format(file.bytes)).font(Typo.figure).foregroundStyle(Ink.inkFaded)
                        }
                    }
                }
            }

            if let path = landmark.places.first?.url.path, landmark.places.count == 1 {
                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(Typo.figure).foregroundStyle(Ink.inkFaded)
                    .lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: Space.s3) {
                Button("Montrer dans le Finder", action: revealInFinder)
                    .buttonStyle(TraceButtonStyle())
                Spacer()
                Button("Fermer", action: onClose)
                    .buttonStyle(NoteButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s5)
        .frame(width: 320, alignment: .leading)
        .background(DogEaredSheet().fill(Ink.paperRaised).sheetShadow(lifted: true))
        .overlay(DogEaredSheet(foldOnly: true).fill(Ink.paperSunken))
        .overlay(DogEaredSheet().stroke(Ink.ink, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fiche de \(landmark.title)")
    }

    private var fileCountText: String {
        let count = landmark.fileCount
        return count == 1 ? "1 fichier" : "\(count.formatted()) fichiers"
    }

    /// Ouvre le Finder sur le lieu (lecture seule : rien n'est modifié).
    private func revealInFinder() {
        let urls = landmark.places.map(\.url)
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls.prefix(20)))
    }
}

/// Feuille au coin supérieur droit corné. `foldOnly` ne dessine que le triangle replié.
struct DogEaredSheet: Shape {
    var fold: CGFloat = 18
    var foldOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if foldOnly {
            path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            path.closeSubpath()
            return path
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        // Le pli lui-même.
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        return path
    }
}

/// Bouton « Note » (tertiaire) : texte souligné d'un filet fin décalé.
struct NoteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.label)
            .foregroundStyle(Ink.ink)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.ink).frame(height: Stroke.hairline)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
