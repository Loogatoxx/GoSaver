import SwiftUI
import AppKit
import GoSaverCore

/// Feuille du convoi : confirmation, suivi en direct, arrivée — et le rapatriement.
/// Rien ne bouge avant le clic sur le Sceau ; le moteur rejuge et vérifie tout de lui-même.
struct ConvoySheet: View {
    let model: AtlasModel

    var body: some View {
        PaperModal(width: 520, onDismiss: dismissible ? { model.closeConvoy() } : nil) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.convoyPhase {
        case .confirmSend(_, let url, let verdict, let reason, let bytes):
            confirmSend(url: url, verdict: verdict, reason: reason, bytes: bytes)
        case .confirmReturn(let record):
            confirmReturn(record)
        case .confirmRelocate(let record):
            confirmRelocate(record)
        case .running(let stage, let done, let total, let returning):
            running(stage: stage, done: done, total: total, returning: returning)
        case .arrived(let name, let bytes, let linked, let place):
            arrived(name: name, bytes: bytes, linked: linked, place: place)
        case .relocated(let name, let place):
            title("\(name) est rangé")
            Text("Désormais dans « \(place) » sur \(harborName).").font(Typo.water).foregroundStyle(Ink.inkFaded)
            closeButton
        case .confirmQuarantine(let url, let bytes):
            confirmQuarantine(url: url, bytes: bytes)
        case .quarantined(let name, let until):
            title("\(name) est au Lazaret")
            Text("Ton Mac est libéré. Récupérable jusqu’au \(until.formatted(date: .long, time: .omitted)) ; ensuite, supprimé pour de bon.")
                .font(Typo.water).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
            closeButton
        case .confirmRestore(let entry):
            twoButtons(title: "Restaurer",
                       text: "« \(URL(fileURLWithPath: entry.original).lastPathComponent) » revient à \(entry.original.replacingOccurrences(of: NSHomeDirectory(), with: "~")) — \(Bytes.format(entry.bytes)) à reprendre sur le disque interne.",
                       action: "Restaurer") { model.confirmRestore() }
        case .confirmDiscard(let entry):
            twoButtons(title: "Supprimer maintenant",
                       text: "« \(URL(fileURLWithPath: entry.original).lastPathComponent) » sera supprimé définitivement de \(harborName), sans attendre la fin du délai. Impossible de le récupérer ensuite.",
                       action: "Supprimer définitivement") { model.confirmDiscard() }
        case .discarded(let name):
            title("\(name) est supprimé")
            Text("Il n’est plus au Lazaret.").font(Typo.water).foregroundStyle(Ink.inkFaded)
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

    @ViewBuilder
    private func arrived(name: String, bytes: Int64, linked: Bool, place: String) -> some View {
        title("\(name) est arrivé sur \(harborName)")
        Text(Bytes.format(bytes)).font(Typo.display).foregroundStyle(Ink.sea)
        Text("rendus au disque interne. Rangé dans « \(place) »."
             + (linked ? " Un lien reste à sa place : l’appli le retrouvera tant que \(harborName) est branché."
                       : " La copie a été vérifiée avant que l’original soit supprimé."))
            .font(Typo.water).foregroundStyle(Ink.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
        closeButton
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
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(verdict.label.uppercased()).font(Typo.region).tracking(Typo.regionTracking)
                .foregroundStyle(PlaceSheet.color(verdict))
            Text(reason).font(Typo.body).foregroundStyle(Ink.ink).fixedSize(horizontal: false, vertical: true)
        }

        GraduatedRule()
        DestinationPicker(model: model)
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
    private func confirmQuarantine(url: URL, bytes: Int64) -> some View {
        title("Mettre au Lazaret")
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(url.lastPathComponent).font(Typo.heading).foregroundStyle(Ink.ink)
            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Typo.figure).foregroundStyle(Ink.inkFaded).lineLimit(1).truncationMode(.middle)
        }
        Text("Il part sur \(harborName), dans « GoSaver Lazaret ». Ton Mac récupère \(Bytes.format(bytes)) tout de suite. Tu peux le restaurer pendant 30 jours ; ensuite, il est supprimé automatiquement.")
            .font(Typo.water).foregroundStyle(Ink.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
        Text("La suppression se fait quand GoSaver est ouvert avec \(harborName) branché.")
            .font(Typo.label).foregroundStyle(Ink.inkFaded)
        HStack(spacing: Space.s3) {
            Button("Annuler") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.cancelAction)
            Spacer()
            Button("Mettre au Lazaret") { model.confirmQuarantine() }
                .buttonStyle(SealButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .padding(.top, Space.s2)
    }

    @ViewBuilder
    private func twoButtons(title text: String, text detail: String, action label: String,
                            perform: @escaping () -> Void) -> some View {
        title(text)
        Text(detail).font(Typo.water).foregroundStyle(Ink.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Space.s3) {
            Button("Annuler") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.cancelAction)
            Spacer()
            Button(label, action: perform)
                .buttonStyle(SealButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func confirmRelocate(_ record: Convoy.Record) -> some View {
        title("Ranger au bon endroit")
        Text(URL(fileURLWithPath: record.original).lastPathComponent).font(Typo.heading).foregroundStyle(Ink.ink)
        Text("Il est sur \(harborName), dans « \(model.harborVolume.map { AtlasModel.shelfName(record, on: $0) } ?? "") ». Le reclasser est un simple renommage : instantané.")
            .font(Typo.water).foregroundStyle(Ink.inkFaded)
            .fixedSize(horizontal: false, vertical: true)
        DestinationPicker(model: model, includeHarbor: false)
        HStack(spacing: Space.s3) {
            Button("Annuler") { model.closeConvoy() }
                .buttonStyle(TraceButtonStyle()).keyboardShortcut(.cancelAction)
            Spacer()
            Button("Ranger") { model.confirmRelocate() }
                .buttonStyle(SealButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(model.destination == .harbor)
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

/// Choix du rayonnage : propositions classées (avec leurs raisons), dossier d'accueil, ou autre dossier.
struct DestinationPicker: View {
    @Bindable var model: AtlasModel
    var includeHarbor = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Destination").regionStyle().foregroundStyle(Ink.inkFaded)
            if !model.suggestionsReady {
                Text("Recherche du meilleur rayonnage…").font(Typo.water).foregroundStyle(Ink.inkFaded)
            } else if model.suggestions.isEmpty {
                Text("Aucun dossier du disque ne ressemble à celui-ci.").font(Typo.water).foregroundStyle(Ink.inkFaded)
            }
            ForEach(model.suggestions) { suggestion in
                option(selected: model.destination == .suggestion(suggestion),
                       title: suggestion.folder.relativePath,
                       detail: (suggestion.merges ? "Fusion. " : "") + (suggestion.reasons.first ?? "")) {
                    model.destination = .suggestion(suggestion)
                }
            }
            if includeHarbor {
                option(selected: model.destination == .harbor, title: "GoSaver Outre-mer",
                       detail: "Dossier d’accueil, à ranger plus tard.") { model.destination = .harbor }
            }
            if case .custom(let url) = model.destination {
                option(selected: true, title: url.lastPathComponent, detail: "Dossier choisi à la main.") {}
            }
            Button("Choisir un autre dossier…", action: pickFolder)
                .buttonStyle(NoteButtonStyle())
        }
    }

    private func option(selected: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                // Repère de légende : carré d'encre, plein quand il est choisi.
                ZStack {
                    Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.rule)
                    if selected { Rectangle().fill(Ink.vermilion).padding(3) }
                }
                .frame(width: 13, height: 13)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(selected ? Typo.bodyStrong : Typo.body).foregroundStyle(Ink.ink)
                        .lineLimit(1).truncationMode(.middle)
                    Text(detail).font(Typo.label).foregroundStyle(Ink.inkFaded)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Fenêtre d'ouverture macOS, limitée à un dossier du disque externe.
    private func pickFolder() {
        guard let volume = model.harborVolume else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = volume.url
        panel.prompt = "Ranger ici"
        panel.message = "Choisis un dossier sur \(volume.name)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Le dossier doit être sur le disque externe, sinon ce ne serait plus un envoi outre-mer.
        guard url.standardizedFileURL.path.hasPrefix(volume.url.standardizedFileURL.path + "/") else { return }
        model.destination = .custom(url)
    }
}
