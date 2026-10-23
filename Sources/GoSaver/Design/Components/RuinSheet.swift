import SwiftUI
import AppKit
import GoSaverCore

/// Fiche d'expertise d'une ruine (docs/DESIGN_SYSTEM.md §6.5) : le résumé de l'enquête,
/// les indices relevés, et le tampon du verdict. Rien n'est déplacé sans clic explicite.
struct RuinSheet: View {
    let ruin: Ruin
    let model: AtlasModel

    var body: some View {
        ViewThatFits(in: .vertical) {
            sheet
            ScrollView { sheet }.scrollIndicators(.never)
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top) {
                Text(ruin.kind.label).regionStyle().foregroundStyle(Ink.inkFaded)
                Spacer()
                Stamp(text: ruin.verdict.stamp, color: ruin.verdict == .isolate ? Ink.vermilion : Ink.ochre)
            }
            Text(ruin.url.lastPathComponent)
                .font(Typo.figure).foregroundStyle(Ink.ink)
                .lineLimit(2).truncationMode(.middle)
            Text(Bytes.format(ruin.bytes)).font(Typo.figureLarge).foregroundStyle(Ink.ink)

            // Le résumé de l'enquête, entre guillemets typographiques, en italique hydrographique.
            Text("« \(ruin.summary) »")
                .font(Typo.water).foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)

            GraduatedRule()

            Text("Indices relevés").regionStyle().foregroundStyle(Ink.inkFaded)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ruin.reasons + extraClues, id: \.self) { clue in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text("—").font(Typo.body).foregroundStyle(Ink.inkFaded).accessibilityHidden(true)
                        Text(clue).font(Typo.body).foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text(ruin.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Typo.figure).foregroundStyle(Ink.inkFaded)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)

            GraduatedRule()
            AdviceSection {
                var choices = model.harborVolume != nil ? ["mettre au Lazaret"] : []
                choices.append("garder")
                let facts = """
                Élément : \(ruin.url.lastPathComponent) (\(ruin.kind.label))
                Chemin : \(ruin.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                Taille : \(Bytes.format(ruin.bytes))
                Verdict de GoSaver : \(ruin.verdict.stamp) — \(ruin.summary)
                Indices : \((ruin.reasons + extraClues).joined(separator: " "))
                """
                return (facts, choices)
            }

            actions
        }
        .padding(Space.s5)
        .frame(width: 340, alignment: .leading)
        .background(DogEaredSheet().fill(Ink.paperRaised).sheetShadow(lifted: true))
        .overlay(DogEaredSheet(foldOnly: true).fill(Ink.paperSunken))
        .overlay(DogEaredSheet().stroke(Ink.ink, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fiche d’expertise : \(ruin.url.lastPathComponent), \(ruin.verdict.stamp.lowercased())")
    }

    /// Indices bruts qui ne figurent pas déjà dans les raisons.
    private var extraClues: [String] {
        var clues: [String] = []
        if let modified = ruin.clues.modified, !ruin.reasons.contains(where: { $0.hasPrefix("Dernière modification") }) {
            clues.append("Modifié le \(modified.formatted(date: .long, time: .omitted)).")
        }
        if let type = ruin.clues.typeDescription, ruin.clues.content == nil { clues.append("Type selon macOS : \(type).") }
        return clues.filter { clue in !ruin.reasons.contains(clue) }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Space.s3) {
            if model.harborVolume != nil {
                Button(Words.toLazaret) {
                    model.whenFree([ruin.url], name: ruin.url.lastPathComponent) {
                        model.convoyPhase = .confirmQuarantine(url: ruin.url, bytes: ruin.bytes)
                    }
                }
                .buttonStyle(TraceButtonStyle())
            }
            Button("Conserver") { model.keepRuin(ruin) }
                .buttonStyle(NoteButtonStyle())
                .help("Ne plus signaler cet élément")
            Spacer()
            Button("Fermer") { model.selectedID = nil }
                .buttonStyle(NoteButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        Button("Montrer dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([ruin.url]) }
            .buttonStyle(NoteButtonStyle())
        if model.harborVolume == nil {
            Text("Branche le disque externe pour pouvoir utiliser « \(Words.lazaret) ».")
                .font(Typo.label).foregroundStyle(Ink.inkFaded)
        }
    }
}

/// Tampon encreur incliné : capitales espacées dans un double cadre, encre légèrement irrégulière.
struct Stamp: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Typo.region).tracking(Typo.regionTracking)
            .foregroundStyle(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .overlay(Rectangle().strokeBorder(color, lineWidth: 1.5))
            .padding(2)
            .overlay(Rectangle().strokeBorder(color.opacity(0.7), lineWidth: 0.6))
            .opacity(0.88)
            .rotationEffect(.degrees(-4))
            .accessibilityLabel("Verdict : \(text.lowercased())")
    }
}
