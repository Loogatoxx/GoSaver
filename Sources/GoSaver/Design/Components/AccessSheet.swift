import SwiftUI
import AppKit
import GoSaverCore

/// Explique et guide l'accès complet au disque, en trois étapes numérotées
/// en chiffres romains, comme les renvois d'une légende de carte.
/// GoSaver ne peut pas s'accorder lui-même cette permission : c'est l'utilisateur qui la donne.
struct AccessSheet: View {
    @Bindable var model: AtlasModel

    var body: some View {
        PaperModal(width: 520, onDismiss: { model.accessSheetOpen = false }) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Ouvrir les zones fermées").font(Typo.title).foregroundStyle(Ink.ink)
                Text("macOS garde certains dossiers sous clé : la corbeille, Mail, Safari, les données de certaines applis. Sans la clé, le géomètre les range dans le Massif sans pouvoir les relever.")
                    .font(Typo.water).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let denied = model.survey?.deniedPaths.count, denied > 0 {
                Text("\(denied) dossiers fermés lors du dernier relevé.")
                    .font(Typo.figure).foregroundStyle(Ink.ink)
            }
            Text("GoSaver ne lit que des noms et des tailles. Rien ne quitte ce Mac.")
                .font(Typo.label).foregroundStyle(Ink.inkFaded)

            GraduatedRule()

            step("I", "Ouvre Réglages Système, à la bonne page.") {
                Button("Ouvrir les Réglages") { NSWorkspace.shared.open(DiskAccess.settingsURL) }
                    .buttonStyle(TraceButtonStyle())
            }
            step("II", "Active GoSaver dans la liste. S’il n’y est pas, clique sur + et choisis-le.") {
                Button("Montrer GoSaver dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(NoteButtonStyle())
            }
            step("III", "macOS propose ensuite de relancer GoSaver : accepte, ou fais-le ici.") {
                Button("Relancer GoSaver", action: relaunch)
                    .buttonStyle(NoteButtonStyle())
            }

            GraduatedRule()

            status

            HStack {
                Spacer()
                Button(model.diskAccess == .granted ? "Fermer" : "Plus tard") { model.accessSheetOpen = false }
                    .buttonStyle(TraceButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.diskAccess == .granted {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Path { p in
                    p.move(to: CGPoint(x: 1, y: 7)); p.addLine(to: CGPoint(x: 5, y: 11)); p.addLine(to: CGPoint(x: 13, y: 2))
                }
                .stroke(Ink.forest, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 13)
                Text("Accès accordé. Refais le relevé pour lever le reste du brouillard.")
                    .font(Typo.bodyStrong).foregroundStyle(Ink.forest)
            }
            Button("Refaire le relevé") {
                model.accessSheetOpen = false
                model.startSurvey()
            }
            .buttonStyle(SealButtonStyle())
        } else {
            Text("En attente : GoSaver vérifie de lui-même à chaque fois que tu reviens dans l’appli.")
                .font(Typo.water).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step<Action: View>(_ number: String, _ text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(number)
                .font(Typo.heading).foregroundStyle(Ink.vermilion)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(text).font(Typo.body).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }

    /// Relance l'appli : macOS n'applique la nouvelle permission qu'à un processus neuf.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
