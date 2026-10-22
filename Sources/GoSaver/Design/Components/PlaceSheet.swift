import SwiftUI
import AppKit
import GoSaverCore

/// Fiche d'un lieu sélectionné (docs/DESIGN_SYSTEM.md §6.5) : une feuille posée
/// sur la carte, coin supérieur droit corné. Données d'abord, métaphore ensuite.
struct PlaceSheet: View {
    let landmark: AtlasModel.Landmark
    let onClose: () -> Void
    /// Demande d'envoi outre-mer (ouvre la feuille de convoi).
    var onSend: ((MobilityVerdict) -> Void)?
    /// Demande de mise au Lazaret (corbeille du disque externe).
    var onQuarantine: (() -> Void)?
    /// Verdict de déplaçabilité vers le disque externe, calculé à l'ouverture (lecture seule).
    @State private var mobility: (verdict: MobilityVerdict, target: TargetVolume?)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("\(Words.terrain(landmark.terrain)) · \(Words.terrainDetail(landmark.terrain))")
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

            GraduatedRule()
            mobilitySection

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
        .task(id: landmark.id) {
            guard let url = landmark.places.first?.url else { return }
            mobility = await Task.detached(priority: .userInitiated) {
                let target = TargetVolume.externalVolumes().first
                return (MobilityJudge(target: target).judge(url), target)
            }.value
        }
    }

    /// « Outre-mer » : peut-on envoyer ce lieu sur le disque externe ?
    @ViewBuilder
    private var mobilitySection: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text(Words.outremer).regionStyle().foregroundStyle(Ink.inkFaded)
                Spacer()
                if let mobility {
                    Text(mobility.verdict.mobility.label.uppercased())
                        .font(Typo.region).tracking(Typo.regionTracking)
                        .foregroundStyle(Self.color(mobility.verdict.mobility))
                }
            }
            if let mobility {
                Text(mobility.verdict.reason)
                    .font(Typo.body).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let advice = mobility.verdict.advice {
                    Text(advice).font(Typo.water).foregroundStyle(Ink.sea)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(mobility.target.map { "Vers \($0.name) (\($0.format.label), \(Bytes.format($0.freeBytes)) libres)" }
                     ?? "Aucun disque externe branché.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                HStack(spacing: Space.s3) {
                    if mobility.target != nil, mobility.verdict.mobility <= .withLink, landmark.places.count == 1, let onSend {
                        Button(Words.sendOutremer) { onSend(mobility.verdict) }
                            .buttonStyle(TraceButtonStyle())
                    }
                    // Le Lazaret accepte aussi le « déconseillé » : on ne compte plus s'en servir.
                    if mobility.target != nil, mobility.verdict.mobility < .forbidden || mobility.verdict.contents != nil,
                       landmark.places.count == 1, let onQuarantine {
                        Button(Words.toLazaret, action: onQuarantine)
                            .buttonStyle(NoteButtonStyle())
                    }
                }
                .padding(.top, Space.s1)
            } else {
                Text("Examen du contenu…").font(Typo.water).foregroundStyle(Ink.inkFaded)
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func color(_ mobility: Mobility) -> Color {
        switch mobility {
        case .free: Ink.forest
        case .withLink: Ink.sea
        case .discouraged: Ink.ochre
        case .forbidden: Ink.vermilion
        }
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
