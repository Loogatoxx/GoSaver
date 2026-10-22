import SwiftUI
import AppKit
import GoSaverCore

/// État de l'atlas, partagé par tous les écrans.
/// `@Observable` : SwiftUI redessine automatiquement ce qui lit une propriété modifiée.
@MainActor
@Observable
final class AtlasModel {
    enum Phase: Equatable {
        case idle
        case surveying
        case surveyed
    }

    private(set) var phase: Phase = .idle
    private(set) var volume = VolumeInfo.of()
    private(set) var places: [Place] = []
    private(set) var survey: Survey?

    // Progression du relevé en cours.
    private(set) var plannedPlaces = 0
    private(set) var surveyedPlaces = 0
    private(set) var filesSoFar = 0
    private(set) var bytesSoFar: Int64 = 0

    /// Part du territoire relevée, de 0 à 1 (sert à lever le brouillard).
    var fogLifted: Double {
        plannedPlaces == 0 ? 0 : Double(surveyedPlaces) / Double(plannedPlaces)
    }

    /// Ce qui se reforme seul et peut partir sans risque : Marais + Grève (corbeille).
    var reclaimableBytes: Int64 {
        guard let survey else { return 0 }
        return survey.bytes(of: .marsh) + survey.bytes(of: .shore)
    }

    func bytes(of terrain: Terrain) -> Int64 {
        if let survey { return survey.bytes(of: terrain) }
        return places.lazy.filter { $0.terrain == terrain }.reduce(0) { $0 + $1.bytes }
    }

    /// Un repère du registre : un lieu, ou un regroupement d'enclaves du même genre.
    struct Landmark: Identifiable {
        let id: String
        let title: String
        let terrain: Terrain
        let bytes: Int64
        let places: [Place]

        var fileCount: Int { places.reduce(0) { $0 + $1.fileCount } }
        /// Les plus gros fichiers de tous les lieux du repère.
        var largestFiles: [FileItem] {
            places.flatMap(\.largestFiles).sorted { $0.bytes > $1.bytes }.prefix(6).map { $0 }
        }
    }

    // MARK: - Sélection

    /// Repère choisi (clic sur la carte ou dans le registre).
    var selectedID: String?
    /// Repère survolé à la souris sur la carte.
    var hoveredID: String?

    /// Retrouve un repère par son identifiant (le même sur la carte et dans le registre).
    func landmark(id: String) -> Landmark? {
        for terrain in Terrain.allCases {
            if let hit = landmarks(of: terrain).first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    func toggleSelection(_ id: String) {
        selectedID = selectedID == id ? nil : id
    }

    /// Lieux d'un terrain, du plus gros au plus petit. Les enclaves de même genre
    /// (les 300 `__pycache__` d'un disque) sont regroupées en un seul repère.
    func landmarks(of terrain: Terrain) -> [Landmark] {
        var groups: [String: [Place]] = [:]
        var singles: [Landmark] = []
        for place in places where place.terrain == terrain {
            if let kind = Self.enclaveKind(place) {
                groups[kind, default: []].append(place)
            } else {
                singles.append(Landmark(id: place.id, title: PlaceNames.display(place), terrain: terrain,
                                        bytes: place.bytes, places: [place]))
            }
        }
        for (kind, members) in groups {
            let total = members.reduce(Int64(0)) { $0 + $1.bytes }
            let title = members.count == 1 ? PlaceNames.display(members[0]) : "\(kind) × \(members.count)"
            singles.append(Landmark(id: "enclave:\(terrain.rawValue):" + kind, title: title, terrain: terrain,
                                    bytes: total, places: members))
        }
        return singles.sorted { $0.bytes > $1.bytes }
    }

    /// Genre d'enclave (« node_modules », « Caches ») si le lieu en est une.
    private static func enclaveKind(_ place: Place) -> String? {
        guard place.isEnclave, let dash = place.name.range(of: " — ") else { return nil }
        return String(place.name[..<dash.lowerBound])
    }

    /// Ce que la carte doit représenter, à partir du relevé terminé.
    func atlasInput() -> AtlasInput? {
        guard let survey else { return nil }
        let regions = Terrain.allCases.compactMap { terrain -> AtlasInput.RegionInput? in
            let bytes = survey.bytes(of: terrain)
            guard bytes > 0 else { return nil }
            let places = landmarks(of: terrain).map { AtlasInput.PlaceInput(id: $0.id, name: $0.title, bytes: $0.bytes) }
            return AtlasInput.RegionInput(terrain: terrain, bytes: bytes, places: places)
        }
        return AtlasInput(capacity: survey.volume.capacity, used: survey.volume.used, regions: regions)
    }

    /// Avant tout relevé : on connaît seulement l'espace occupé. L'île a sa vraie taille,
    /// mais sa géographie est inconnue (une seule terre, sous le brouillard).
    func unsurveyedInput() -> AtlasInput {
        AtlasInput(capacity: volume.capacity, used: volume.used,
                   regions: [.init(terrain: .fields, bytes: max(volume.used, 1), places: [])])
    }

    private var task: Task<Void, Never>?

    // MARK: - Accès complet au disque

    private(set) var diskAccess: DiskAccess.Status = DiskAccess.status()
    var accessSheetOpen = false

    /// Relit la permission (appelé quand l'appli redevient active).
    func refreshDiskAccess() {
        diskAccess = DiskAccess.status()
        Log.access.notice("accès complet au disque : \(String(describing: self.diskAccess), privacy: .public)")
    }

    // MARK: - Outre-mer (convois vers le disque externe)

    enum ConvoyPhase: Equatable {
        case closed
        /// Confirmation d'envoi d'un repère vers la destination.
        case confirmSend(id: String, url: URL, verdict: Mobility, reason: String, bytes: Int64)
        /// Confirmation de rapatriement.
        case confirmReturn(Convoy.Record)
        /// Choix d'un meilleur rayonnage pour un convoi déjà arrivé.
        case confirmRelocate(Convoy.Record)
        case running(stage: Convoy.Stage, done: Int64, total: Int64, returning: Bool)
        case arrived(name: String, bytes: Int64, linked: Bool, place: String)
        case relocated(name: String, place: String)
        /// Lazaret : confirmation, arrivée, restauration, suppression immédiate.
        case confirmQuarantine(url: URL, bytes: Int64)
        case confirmQuarantineRuins(count: Int, bytes: Int64)
        case quarantined(name: String, until: Date)
        case confirmRestore(Lazaret.Entry)
        case confirmDiscard(Lazaret.Entry)
        case discarded(name: String)
        case returned(name: String)
        case failed(String)
    }

    var convoyPhase: ConvoyPhase = .closed
    /// Disque externe visé (le premier branché), relu à la demande.
    private(set) var harborVolume: TargetVolume? = AtlasModel.currentHarbor()
    /// Ce qui est déjà outre-mer, d'après le registre de bord du disque.
    private(set) var convoys: [Convoy.Record] = []

    /// Index des dossiers du disque externe (construit en arrière-plan quand il est branché).
    private(set) var placement: Placement?
    private var indexedVolume: URL?

    /// Destination choisie dans la feuille d'envoi.
    enum Destination: Equatable {
        case harbor
        case suggestion(PlacementSuggestion)
        case custom(URL)
    }
    /// Propositions pour le convoi en préparation (vide tant qu'elles se calculent).
    private(set) var suggestions: [PlacementSuggestion] = []
    private(set) var suggestionsReady = false
    var destination: Destination = .harbor

    /// Disque externe visé. `GOSAVER_HARBOR=/Volumes/Test` (développement) force un autre disque,
    /// pour essayer les convois sans toucher au vrai disque externe.
    static func currentHarbor() -> TargetVolume? {
        if let forced = ProcessInfo.processInfo.environment["GOSAVER_HARBOR"] {
            return TargetVolume.detect(URL(fileURLWithPath: forced))
        }
        let volumes = TargetVolume.externalVolumes()
        // Réglage « disque de destination » : celui-là s'il est branché, sinon le premier venu.
        let chosen = UserDefaults.standard.string(forKey: "disqueExterne") ?? ""
        return volumes.first { $0.url.path == chosen } ?? volumes.first
    }

    /// Ce qui attend au Lazaret, de la plus proche expiration à la plus lointaine.
    private(set) var lazaretEntries: [Lazaret.Entry] = []
    /// Éléments supprimés automatiquement (délai écoulé) lors de la dernière vérification.
    private(set) var lastPurge: [Lazaret.Entry] = []

    func refreshHarbor() {
        harborVolume = Self.currentHarbor()
        convoys = harborVolume.map { Convoy(target: $0).records() } ?? []
        if let harbor = harborVolume {
            // Le Lazaret se vide de lui-même : ce qui a dépassé ses 30 jours part maintenant.
            let lazaret = Lazaret(target: harbor, retention: Preferences.shared.lazaretRetention)
            let purged = lazaret.purgeExpired()
            if !purged.isEmpty {
                lastPurge = purged
                Log.convoy.notice("Lazaret : \(purged.count) élément(s) expiré(s) supprimé(s)")
            }
            lazaretEntries = lazaret.entries()
        } else {
            lazaretEntries = []
        }
        guard let volume = harborVolume?.url else { placement = nil; indexedVolume = nil; return }
        guard volume != indexedVolume else { return }
        indexedVolume = volume
        Task {
            // ~7 s sur un disque de 3 000 dossiers : hors du fil principal.
            placement = await Task.detached(priority: .utility) { Placement.index(volume) }.value
        }
    }

    func prepareSend(_ landmark: Landmark, verdict: MobilityVerdict) {
        guard let url = landmark.places.first?.url else { return }
        convoyPhase = .confirmSend(id: landmark.id, url: url, verdict: verdict.mobility,
                                   reason: verdict.reason, bytes: verdict.bytesOnTarget ?? landmark.bytes)
        // Un envoi « avec lien » garde un dossier à lui : on ne propose pas de fusion.
        suggest(for: url, allowMerge: verdict.mobility == .free)
    }

    func prepareReturn(_ record: Convoy.Record) { convoyPhase = .confirmReturn(record) }

    // MARK: Lazaret

    func prepareQuarantine(_ landmark: Landmark) {
        guard let url = landmark.places.first?.url else { return }
        convoyPhase = .confirmQuarantine(url: url, bytes: landmark.bytes)
    }
    func prepareRestore(_ entry: Lazaret.Entry) { convoyPhase = .confirmRestore(entry) }
    func prepareDiscard(_ entry: Lazaret.Entry) { convoyPhase = .confirmDiscard(entry) }

    func confirmQuarantine() {
        guard case .confirmQuarantine(let url, let bytes) = convoyPhase, let target = harborVolume else { return }
        let lazaret = Lazaret(target: target, retention: Preferences.shared.lazaretRetention)
        convoyPhase = .running(stage: .judging, done: 0, total: bytes, returning: false)
        Task {
            let outcome: Result<Lazaret.Entry, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try lazaret.quarantine(url) { p in
                        Task { @MainActor in
                            if case .running = self.convoyPhase {
                                self.convoyPhase = .running(stage: p.stage, done: p.bytesDone, total: max(p.bytesTotal, bytes), returning: false)
                            }
                        }
                    }
                }
            }.value
            switch outcome {
            case .success(let entry):
                if let survey {
                    apply(.finished(survey.removing([(url: url, bytes: entry.bytes)], volume: .of())))
                }
                selectedID = nil
                landRevision += 1
                refreshHarbor()
                convoyPhase = .quarantined(name: url.lastPathComponent, until: entry.expires)
            case .failure(let error):
                convoyPhase = .failed(error.localizedDescription)
            }
        }
    }

    func confirmRestore() {
        guard case .confirmRestore(let entry) = convoyPhase, let target = harborVolume else { return }
        convoyPhase = .running(stage: .copying, done: 0, total: entry.bytes, returning: true)
        Task {
            let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                Result { try Lazaret(target: target).restore(entry) }
            }.value
            switch outcome {
            case .success:
                refreshHarbor()
                volume = .of()
                convoyPhase = .returned(name: URL(fileURLWithPath: entry.original).lastPathComponent)
            case .failure(let error):
                convoyPhase = .failed(error.localizedDescription)
            }
        }
    }

    func confirmDiscard() {
        guard case .confirmDiscard(let entry) = convoyPhase, let target = harborVolume else { return }
        do {
            try Lazaret(target: target).discardNow(entry)
            refreshHarbor()
            convoyPhase = .discarded(name: URL(fileURLWithPath: entry.original).lastPathComponent)
        } catch {
            convoyPhase = .failed(error.localizedDescription)
        }
    }

    func prepareRelocate(_ record: Convoy.Record) {
        convoyPhase = .confirmRelocate(record)
        suggest(for: URL(fileURLWithPath: record.destination), allowMerge: !record.linked)
    }

    /// Calcule les meilleurs rayonnages (lecture seule) et présélectionne le premier.
    private func suggest(for url: URL, allowMerge: Bool) {
        suggestions = []
        suggestionsReady = false
        destination = .harbor
        Task {
            // L'index peut être encore en cours de construction : on l'attend un peu.
            for _ in 0..<40 where placement == nil { try? await Task.sleep(for: .milliseconds(250)) }
            guard let placement else { suggestionsReady = true; return }
            let found = await Task.detached(priority: .userInitiated) {
                placement.suggestions(for: url).filter { allowMerge || !$0.merges }
                    .filter { !url.path.hasPrefix($0.folder.url.path + "/") || $0.merges }
            }.value
            suggestions = found
            suggestionsReady = true
            if let first = found.first { destination = .suggestion(first) }
        }
    }

    /// Dossier et mode d'arrivée correspondant au choix de la feuille.
    private var chosenFolder: (folder: URL?, merge: Bool) {
        switch destination {
        case .harbor: (nil, false)
        case .suggestion(let s): (s.folder.url, s.merges)
        case .custom(let url): (url, false)
        }
    }

    func confirmRelocate() {
        Log.convoy.notice("Ranger cliqué ; phase : \(String(describing: self.convoyPhase), privacy: .public) ; destination : \(String(describing: self.destination), privacy: .public)")
        guard case .confirmRelocate(let record) = convoyPhase, let target = harborVolume,
              let folder = chosenFolder.folder else { return }
        let merge = chosenFolder.merge
        Task {
            let outcome: Result<Convoy.Record, Error> = await Task.detached(priority: .userInitiated) {
                Result { try Convoy(target: target).relocate(record, to: folder, merge: merge) }
            }.value
            Log.convoy.notice("reclassement : \(String(describing: outcome), privacy: .public) ; phase avant : \(String(describing: self.convoyPhase), privacy: .public)")
            switch outcome {
            case .success(let moved):
                refreshHarbor()
                convoyPhase = .relocated(name: URL(fileURLWithPath: record.original).lastPathComponent,
                                         place: Self.shelfName(moved, on: target))
            case .failure(let error):
                convoyPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// « Archives/Downloads-images-2026-09 » : où l'envoi se trouve, depuis la racine du disque.
    static func shelfName(_ record: Convoy.Record, on target: TargetVolume) -> String {
        let base = target.url.path + "/"
        let path = record.mergedItems == nil ? URL(fileURLWithPath: record.destination).deletingLastPathComponent().path : record.destination
        let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
        return relative.isEmpty ? target.name : relative
    }
    func closeConvoy() { convoyPhase = .closed }

    /// Lance l'envoi confirmé. Le moteur rejuge et vérifie tout lui-même.
    func confirmSend() {
        guard case .confirmSend(_, let url, _, _, let bytes) = convoyPhase, let target = harborVolume else { return }
        let (folder, merge) = chosenFolder
        convoyPhase = .running(stage: .judging, done: 0, total: bytes, returning: false)
        Task {
            let outcome: Result<Convoy.Record, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try Convoy(target: target).send(url, into: folder, merge: merge) { p in
                        Task { @MainActor in
                            if case .running = self.convoyPhase {
                                self.convoyPhase = .running(stage: p.stage, done: p.bytesDone, total: max(p.bytesTotal, bytes), returning: false)
                            }
                        }
                    }
                }
            }.value
            switch outcome {
            case .success(let record):
                if let survey {
                    apply(.finished(survey.removing([(url: url, bytes: record.bytes)], volume: .of())))
                }
                selectedID = nil
                landRevision += 1
                refreshHarbor()
                convoyPhase = .arrived(name: url.lastPathComponent, bytes: record.bytes, linked: record.linked,
                                       place: Self.shelfName(record, on: target))
            case .failure(let error):
                convoyPhase = .failed(error.localizedDescription)
            }
        }
    }

    /// Lance le rapatriement confirmé.
    func confirmReturn() {
        guard case .confirmReturn(let record) = convoyPhase, let target = harborVolume else { return }
        convoyPhase = .running(stage: .copying, done: 0, total: record.bytes, returning: true)
        Task {
            let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    try Convoy(target: target).bringBack(record) { p in
                        Task { @MainActor in
                            if case .running = self.convoyPhase {
                                self.convoyPhase = .running(stage: p.stage, done: p.bytesDone, total: record.bytes, returning: true)
                            }
                        }
                    }
                }
            }.value
            switch outcome {
            case .success:
                refreshHarbor()
                volume = .of()
                convoyPhase = .returned(name: URL(fileURLWithPath: record.original).lastPathComponent)
            case .failure(let error):
                convoyPhase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Assèchement

    enum DrainPhase: Equatable {
        case closed
        case planning
        case confirming
        case draining(removed: Int64)
        case done(removed: Int64, failures: Int)
    }

    private(set) var drainPhase: DrainPhase = .closed
    private(set) var drainPlan: Drainer.Plan?
    /// Vider aussi la corbeille (définitif) : décoché par défaut, c'est à l'utilisateur de le vouloir.
    var includeTrash = false
    /// Change à chaque modification du terrain : la carte se reconstruit (avec érosion).
    private(set) var landRevision = 0

    /// Prépare le plan (lecture seule) et ouvre la feuille de confirmation.
    func prepareDrain() {
        drainPhase = .planning
        includeTrash = Preferences.shared.trashCheckedByDefault
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { RunningApp(bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "") }
        Task {
            let plan = await Task.detached(priority: .userInitiated) { Drainer.standard().plan(running: running) }.value
            drainPlan = plan
            drainPhase = .confirming
        }
    }

    /// Ce que la feuille propose réellement d'assécher, selon la case « corbeille ».
    var drainSelection: [Drainer.Item] {
        (drainPlan?.items ?? []).filter { includeTrash || $0.kind != .trash }
    }

    /// Mode instantané : affiche la feuille de confirmation pour un plan donné (rien n'est supprimé).
    func previewDrain(_ plan: Drainer.Plan) {
        drainPlan = plan
        drainPhase = .confirming
    }

    func cancelDrain() {
        drainPhase = .closed
        drainPlan = nil
    }

    /// Supprime pour de bon ce que la feuille a montré. Appelé seulement par le bouton de confirmation.
    func confirmDrain() {
        guard let plan = drainPlan, drainPhase == .confirming else { return }
        let chosen = plan.keeping(includeTrash ? Set(Drainer.Kind.allCases) : [.cache, .log])
        drainPhase = .draining(removed: 0)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Drainer.standard().execute(chosen) { removed in
                    Task { @MainActor in self.drainPhase = .draining(removed: removed) }
                }
            }.value
            let removedSet = Set(result.failures.map(\.path))
            let removed = chosen.items.filter { !removedSet.contains($0.url.path) }.map { (url: $0.url, bytes: $0.bytes) }
            if let survey {
                apply(.finished(survey.removing(removed, volume: .of())))
            } else {
                volume = .of()
            }
            selectedID = nil
            landRevision += 1
            drainPhase = .done(removed: result.removedBytes, failures: result.failures.count)
        }
    }

    func startSurvey() {
        guard phase != .surveying else { return }
        phase = .surveying
        selectedID = nil
        hoveredID = nil
        places = []
        survey = nil
        plannedPlaces = 0
        surveyedPlaces = 0
        let excluded = Preferences.shared.excludedURLs
        task = Task {
            for await event in Surveyor(excluded: excluded).survey() {
                // Fin du relevé : l'expertise des ruines passe avant que la carte ne se dessine.
                if case .finished(let survey) = event {
                    apply(.finished(await expertise(of: survey)))
                    // Réglage « isoler automatiquement » : les ruines sûres partent au Lazaret sans demander.
                    if Preferences.shared.autoIsolateRuins, harborVolume != nil, !safeRuins.isEmpty {
                        convoyPhase = .confirmQuarantineRuins(count: safeRuins.count, bytes: safeRuins.reduce(0) { $0 + $1.bytes })
                        confirmQuarantineRuins()
                    }
                } else {
                    apply(event)
                }
            }
        }
    }

    // MARK: - Ruines

    /// Trouvailles de l'expertise (dernier relevé), sauf celles que l'utilisateur a choisi de conserver.
    private(set) var ruins: [Ruin] = []
    var visibleRuins: [Ruin] { ruins.filter { !keptRuins.contains($0.id) } }
    /// Ruines que l'utilisateur a décidé de garder : on ne les signale plus.
    private(set) var keptRuins: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "ruinesConservees") ?? [])

    func ruin(id: String) -> Ruin? { visibleRuins.first { $0.id == id } }

    /// Réglages : réafficher les ruines qu'on avait choisi de conserver.
    func resetKeptRuins() {
        keptRuins = []
        UserDefaults.standard.removeObject(forKey: "ruinesConservees")
    }

    func keepRuin(_ ruin: Ruin) {
        keptRuins.insert(ruin.id)
        UserDefaults.standard.set(Array(keptRuins), forKey: "ruinesConservees")
        if selectedID == ruin.id { selectedID = nil }
    }

    /// Lance l'expertise (lecture seule) et range les données d'applis disparues dans le terrain « Ruines ».
    func expertise(of survey: Survey) async -> Survey {
        let orphanAge = TimeInterval(Preferences.shared.orphanDays) * 86_400
        let found = await Task.detached(priority: .userInitiated) {
            var archaeologist = Archaeologist()
            archaeologist.orphanAge = orphanAge
            return archaeologist.excavate()
        }.value
        ruins = found
        let orphans = Set(found.filter { $0.kind == .orphanAppData && !keptRuins.contains($0.id) }.map(\.url.path))
        guard !orphans.isEmpty else { return survey }
        let places = survey.places.map { place in
            orphans.contains(place.url.path) ? place.with(terrain: .ruins) : place
        }
        return Survey(volume: survey.volume, places: places, deniedPaths: survey.deniedPaths, duration: survey.duration)
    }

    /// Ruines sûres (verdict « à isoler »), prêtes pour le Lazaret.
    var safeRuins: [Ruin] { visibleRuins.filter { $0.verdict == .isolate } }

    func prepareQuarantineRuins() {
        let list = safeRuins
        guard !list.isEmpty else { return }
        convoyPhase = .confirmQuarantineRuins(count: list.count, bytes: list.reduce(0) { $0 + $1.bytes })
    }

    /// Met les ruines sûres au Lazaret, une par une ; un échec n'arrête pas les suivantes.
    func confirmQuarantineRuins() {
        guard case .confirmQuarantineRuins(_, let total) = convoyPhase, let target = harborVolume else { return }
        let list = safeRuins
        let lazaret = Lazaret(target: target, retention: Preferences.shared.lazaretRetention)
        convoyPhase = .running(stage: .copying, done: 0, total: total, returning: false)
        Task {
            var moved: [(url: URL, bytes: Int64)] = []
            var failures: [String] = []
            var until = Date()
            for ruin in list {
                let result: Result<Lazaret.Entry, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try lazaret.quarantine(ruin.url) }
                }.value
                switch result {
                case .success(let entry):
                    moved.append((ruin.url, entry.bytes))
                    until = entry.expires
                    convoyPhase = .running(stage: .copying, done: moved.reduce(0) { $0 + $1.bytes }, total: total, returning: false)
                case .failure(let error):
                    failures.append("\(ruin.url.lastPathComponent) : \(error.localizedDescription)")
                }
            }
            ruins.removeAll { ruin in moved.contains { $0.url == ruin.url } }
            if let survey { apply(.finished(survey.removing(moved, volume: .of()))) }
            selectedID = nil
            landRevision += 1
            refreshHarbor()
            convoyPhase = failures.isEmpty
                ? .quarantined(name: "\(moved.count) ruine\(moved.count > 1 ? "s" : "")", until: until)
                : .failed("\(moved.count) ruine(s) mise(s) au Lazaret ; \(failures.count) n’ont pas pu partir :\n" + failures.joined(separator: "\n"))
        }
    }

    /// Applique un relevé déjà fait (mode instantané).
    func load(_ survey: Survey) async {
        apply(.finished(await expertise(of: survey)))
    }

    /// Lieux reçus mais pas encore affichés : on les publie par paquets, au rythme
    /// des évènements de progression (10 par seconde). Publier chaque lieu un par un
    /// redessinerait le registre 1 500 fois et saturerait le fil principal.
    private var pending: [Place] = []
    private var pendingSurveyed = 0

    private func apply(_ event: SurveyEvent) {
        switch event {
        case .planned(let count):
            plannedPlaces = count
        case .progress(let files, let bytes):
            filesSoFar = files
            bytesSoFar = bytes
            flush()
        case .surveyed(let place):
            // Les enclaves (node_modules…) ne sont pas des lieux prévus : elles ne comptent pas dans la progression.
            if !place.isEnclave { pendingSurveyed += 1 }
            pending.append(place)
        case .finished(let result):
            pending = []
            pendingSurveyed = 0
            survey = result
            volume = result.volume
            places = result.places
            surveyedPlaces = plannedPlaces
            phase = .surveyed
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        places.append(contentsOf: pending)
        surveyedPlaces = min(surveyedPlaces + pendingSurveyed, plannedPlaces)
        pending = []
        pendingSurveyed = 0
    }
}
