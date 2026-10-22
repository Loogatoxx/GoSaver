import SwiftUI
import AppKit
import GoSaverCore

@main
struct GoSaverApp: App {
    @State private var model = AtlasModel()

    init() {
        Snapshot.runIfRequested()
        Typo.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("GoSaver") {
            RootView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                // Au démarrage : registre de bord du disque externe et index de ses dossiers.
                .onAppear { model.refreshHarbor() }
                // Au retour des Réglages, on revérifie la permission.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.refreshDiskAccess()
                    model.refreshHarbor()
                }
                // Disque branché ou débranché : l'Outre-mer apparaît ou disparaît.
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
                    model.refreshHarbor()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
                    model.refreshHarbor()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Menu GoSaver › Accès complet au disque… : toujours accessible, relevé fait ou non.
            CommandGroup(after: .appInfo) {
                Button("Accès complet au disque…") { model.accessSheetOpen = true }
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

/// Écran principal provisoire : relevé réel + registre, en attendant la carte 3D
/// qui occupera la grande zone de gauche.
struct RootView: View {
    let model: AtlasModel

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Ink.paper
                // ImageRenderer (mode instantané) ne sait pas dessiner une vue RealityKit.
                if !Snapshot.isActive { AtlasMapView(model: model) }
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s5) { headline }
                        .modifier(PaperHalo())
                        // Quand une fiche est ouverte, elle prend la place de l'en-tête.
                        .opacity(model.selectedID == nil ? 1 : 0)
                        .allowsHitTesting(false)
                    Spacer()
                    HStack(alignment: .bottom, spacing: Space.s5) {
                        Cartouche(
                            title: model.volume.name,
                            subtitle: "Relevé topographique du disque interne",
                            survey: "Échelle 1 : 10 Go · \(Date.now.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .frame(maxWidth: 340)
                        Spacer()
                        action
                    }
                    ScaleBar(capacity: model.volume.capacity, used: model.volume.used,
                             reclaimable: model.reclaimableBytes)
                }
                .padding(Space.s7)

                // La fiche du lieu sélectionné, au-dessus de tout, à la place de l'en-tête.
                if let id = model.selectedID, let landmark = model.landmark(id: id) {
                    PlaceSheet(landmark: landmark, onClose: { model.selectedID = nil },
                               onSend: { verdict in model.prepareSend(landmark, verdict: verdict) })
                        .padding(.top, Space.s7)
                        .padding(.leading, Space.s7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(id)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(Motion.settle, value: model.selectedID)
            Ledger(model: model)
                .frame(width: 340)
        }
        .background(Ink.paper)
        .overlay {
            if model.convoyPhase != .closed {
                ConvoySheet(model: model)
                    .transition(.opacity)
            } else if model.drainPhase != .closed {
                DrainSheet(model: model)
                    .transition(.opacity)
            } else if model.accessSheetOpen {
                AccessSheet(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: model.drainPhase != .closed)
        .animation(Motion.settle, value: model.accessSheetOpen)
        .animation(Motion.settle, value: model.convoyPhase == .closed)
    }

    /// Le grand chiffre : ce qui compte le plus à cet instant.
    @ViewBuilder
    private var headline: some View {
        switch model.phase {
        case .idle:
            Text("Atlas du disque").regionStyle().foregroundStyle(Ink.inkFaded)
            Text(Bytes.format(model.volume.free)).font(Typo.display).foregroundStyle(Ink.ink)
            Text("de mer libre autour de l’île. Le relevé n’a pas encore commencé.")
                .font(Typo.water).foregroundStyle(Ink.sea)
        case .surveying:
            Text("Relevé en cours").regionStyle().foregroundStyle(Ink.inkFaded)
            Text(Bytes.format(model.bytesSoFar))
                .font(Typo.display).foregroundStyle(Ink.ink)
                .contentTransition(.numericText())
            Text("relevés dans \(model.surveyedPlaces) lieux sur \(model.plannedPlaces). Le brouillard se lève.")
                .font(Typo.water).foregroundStyle(Ink.inkFaded)
        case .surveyed:
            Text("Relevé terminé").regionStyle().foregroundStyle(Ink.inkFaded)
            Text(Bytes.format(model.reclaimableBytes))
                .font(Typo.display).foregroundStyle(Ink.vermilion)
            Text("de marais et de grève à assécher sans risque : ils se reforment seuls ou sont déjà à la corbeille.")
                .font(Typo.water).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch model.phase {
        case .idle:
            Button("Lancer le relevé") { model.startSurvey() }
                .buttonStyle(SealButtonStyle())
                .keyboardShortcut(.defaultAction)
        case .surveying:
            Button("Relevé…") {}
                .buttonStyle(SealButtonStyle())
                .disabled(true)
        case .surveyed:
            VStack(alignment: .trailing, spacing: Space.s3) {
                Button("Assécher les marais") { model.prepareDrain() }
                    .buttonStyle(SealButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.reclaimableBytes == 0)
                Button("Refaire le relevé") { model.startSurvey() }
                    .buttonStyle(NoteButtonStyle())
            }
        }
    }
}

/// Halo de papier autour du texte posé sur la carte : la même technique que les
/// noms de lieux imprimés, pour rester lisible au-dessus du relief.
struct PaperHalo: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Ink.paper, radius: 2)
            .shadow(color: Ink.paper, radius: 4)
            .shadow(color: Ink.paper.opacity(0.8), radius: 10)
    }
}
