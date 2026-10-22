import SwiftUI
import GoSaverCore

/// Feuille du convoi : confirmation, suivi en direct, arrivée — et le rapatriement.
/// Rien ne bouge avant le clic sur le Sceau ; le moteur rejuge et vérifie tout de lui-même.
struct ConvoySheet: View {
    let model: AtlasModel

    var body: some View {
        PaperModal(width: 500, onDismiss: dismissible ? { model.closeConvoy() } : nil) {
            switch model.convoyPhase {
            case .confirmSend(_, let url, let verdict, let reason, let bytes):
                confirmSend(url: url, verdict: verdict, reason: reason, bytes: bytes)
            case .confirmReturn(let record):
                confirmReturn(record)
            case .running(let stage, let done, let total, let returning):
                running(stage: stage, done: done, total: total, returning: returning)
            case .arrived(let name, let bytes, let linked):
                title("\(name) est arrivé sur \(harborName)")
                Text(Bytes.format(bytes)).font(Typo.display).foregroundStyle(Ink.sea)
                Text(linked
                     ? "rendus au disque interne. Un lien reste à sa place : l’appli le retrouvera tant que \(harborName) est branché."
                     : "rendus au disque interne. La copie a été vérifiée avant que l’original soit supprimé.")
                    .font(Typo.water).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
                closeButton
            case .returned(let name):
                title("\(name) est revenu à sa place")
                Text("La copie a été vérifiée, puis retirée de \(harborName).")
                    .font(Typo.water).foregroundStyle(Ink.inkFaded)
                closeButton
            case .failed(let message):
                title("Le convoi s’est arrêté")
                Text(message).font(Typo.body).foregroundStyle(Ink.ochre)
                    .fixedSize(horizontal: false, vertical: true)
                closeButton
            case .closed:
                EmptyView()
            }
        }
    }

    private var harborName: String { model.harborVolume?.name ?? "le disque externe" }

    private var dismissible: Bool {
        if case .running = model.convoyPhase { return false }
        return true
    }

    // MARK: - Étapes

    @ViewBuilder
    private func confirmSend(url: URL, verdict: Mobility, reason: String, bytes: Int64) -> some View {
        title("Envoyer outre-mer")
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(url.lastPathComponent).font(Typo.heading).foregroundStyle(Ink.ink)
            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Typo.figure).foregroundStyle(Ink.inkFaded).lineLimit(1).truncationMode(.middle)
        }
        if let harbor = model.harborVolume {
            Text("Vers \(harbor.name) (\(harbor.format.label), \(Bytes.format(harbor.freeBytes)) libres), dans « GoSaver Outre-mer ».")
                .font(Typo.label).foregroundStyle(Ink.inkFaded)
        }
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(verdict.label.uppercased()).font(Typo.region).tracking(Typo.regionTracking)
                .foregroundStyle(PlaceSheet.color(verdict))
            Text(reason).font(Typo.body).foregroundStyle(Ink.ink).fixedSize(horizontal: false, vertical: true)
        }

        GraduatedRule()

        VStack(alignment: .leading, spacing: Space.s2) {
            stepLine("I", "Copie sur \(harborName).")
            stepLine("II", "Vérification : chaque fichier, sa taille et son empreinte.")
            stepLine("III", verdict == .withLink
                     ? "L’original est remplacé par un lien vers la copie."
                     : "L’original est supprimé, seulement après la vérification.")
        }

        HStack(spacing: Space.s3) {
            Button("Annuler") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.cancelAction)
            Spacer()
            Button("Envoyer \(Bytes.format(bytes))") { model.confirmSend() }
                .buttonStyle(SealButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .padding(.top, Space.s2)
    }

    @ViewBuilder
    private func confirmReturn(_ record: Convoy.Record) -> some View {
        title("Rapatrier")
        Text(URL(fileURLWithPath: record.original).lastPathComponent).font(Typo.heading).foregroundStyle(Ink.ink)
        Text("Retour vers \(record.original.replacingOccurrences(of: NSHomeDirectory(), with: "~")) — \(Bytes.format(record.bytes)) à reprendre sur le disque interne.")
            .font(Typo.water).foregroundStyle(Ink.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Space.s3) {
            Button("Annuler") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.cancelAction)
            Spacer()
            Button("Rapatrier") { model.confirmReturn() }
                .buttonStyle(SealButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func running(stage: Convoy.Stage, done: Int64, total: Int64, returning: Bool) -> some View {
        title(returning ? "Rapatriement en cours" : "Convoi en route")
        Text(stageText(stage)).font(Typo.water).foregroundStyle(Ink.inkFaded)
        // Échelle graduée de la traversée : cases d'encre pour ce qui est passé.
        ScaleBar(capacity: max(total, 1), used: min(done, max(total, 1)))
            .accessibilityLabel("\(Bytes.format(done)) sur \(Bytes.format(total))")
        Text("Ne débranche pas \(harborName) pendant la traversée.")
            .font(Typo.label).foregroundStyle(Ink.ochre)
    }

    private func stageText(_ stage: Convoy.Stage) -> String {
        switch stage {
        case .judging: "Dernier examen avant le départ…"
        case .copying: "Copie des fichiers…"
        case .verifying: "Vérification de la copie…"
        case .replacing: "Remplacement de l’original…"
        case .done: "Arrivé."
        }
    }

    // MARK: - Pièces

    private func title(_ text: String) -> some View {
        Text(text).font(Typo.title).foregroundStyle(Ink.ink).fixedSize(horizontal: false, vertical: true)
    }

    private func stepLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(number).font(Typo.heading).foregroundStyle(Ink.vermilion).frame(width: 26, alignment: .trailing)
            Text(text).font(Typo.body).foregroundStyle(Ink.ink)
        }
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button("Fermer") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }
}
