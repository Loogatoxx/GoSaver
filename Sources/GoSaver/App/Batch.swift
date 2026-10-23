import SwiftUI
import AppKit
import GoSaverCore

/// Actions en lot depuis le Registre : on coche plusieurs lieux, puis une seule action pour tous.
/// Chaque élément est vérifié séparément ; ceux qui ne peuvent pas suivre sont écartés avec leur raison.
enum BatchAction: String, Sendable {
    case trash, outremer, lazaret

    @MainActor var title: String {
        switch self {
        case .trash: "Supprimer"
        case .outremer: Words.sendOutremer
        case .lazaret: Words.toLazaret
        }
    }
}

struct BatchItem: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    let url: URL
    let title: String
    let bytes: Int64
    /// Raison pour laquelle l'élément est écarté (`nil` : il suit le lot).
    var refusal: String?
    /// Précision affichée (« avec 3 restes », « → Archives/Images »…).
    var note: String?
    /// Ce qui part réellement : l'élément, plus les restes d'une appli désinstallée.
    var targets: [URL]
    /// Dossier de destination proposé (outre-mer).
    var destination: URL?
}

struct BatchPlan: Equatable, Sendable {
    let action: BatchAction
    let items: [BatchItem]
    var ready: [BatchItem] { items.filter { $0.refusal == nil } }
    var refused: [BatchItem] { items.filter { $0.refusal != nil } }
    var bytes: Int64 { ready.reduce(0) { $0 + $1.bytes } }
}

extension AtlasModel {
    // MARK: - Sélection multiple

    func togglePick(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func setPicked(_ ids: [String], _ on: Bool) {
        if on { picked.formUnion(ids) } else { picked.subtract(ids) }
    }

    func endSelection() {
        selecting = false
        picked = []
    }

    /// Emplacements réels derrière la sélection (un groupe « node_modules × 80 » en donne 80).
    var pickedLocations: [(url: URL, title: String, bytes: Int64)] {
        picked.flatMap { id -> [(URL, String, Int64)] in
            if let ruin = ruin(id: id) { return [(ruin.url, ruin.url.lastPathComponent, ruin.bytes)] }
            guard let landmark = landmark(id: id) else { return [] }
            return landmark.places.map { place in
                (place.url, landmark.places.count == 1 ? landmark.title : PlaceNames.display(place), place.bytes)
            }
        }
        .sorted { $0.2 > $1.2 }
        .map { (url: $0.0, title: $0.1, bytes: $0.2) }
    }

    var pickedBytes: Int64 { pickedLocations.reduce(0) { $0 + $1.bytes } }

    // MARK: - Préparation

    /// Vérifie chaque élément pour l'action demandée (lecture seule), puis ouvre la feuille récapitulative.
    func prepareBatch(_ action: BatchAction) {
        let locations = pickedLocations
        guard !locations.isEmpty else { return }
        let harbor = harborVolume
        let placement = placement
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let home = NSHomeDirectory()
        convoyPhase = .running(stage: .judging, done: 0, total: 0, returning: false)
        Task {
            let items = await Task.detached(priority: .userInitiated) {
                let checked = locations.map { location in
                    Self.check(location, for: action, harbor: harbor, placement: placement, running: running, home: home)
                }
                // Une appli désinstallée emporte ses données : celles-ci ne doivent pas apparaître une seconde fois.
                let covered = Set(checked.filter { $0.refusal == nil }.flatMap { $0.targets.dropFirst() }.map(\.path))
                // Garde-fou : rien de ce qu'un programme tient ouvert ne bouge.
                let held = InUse.holders(of: locations.map(\.url))
                return checked.filter { !covered.contains($0.url.path) }.map { item in
                    guard item.refusal == nil, let who = held[item.url] else { return item }
                    var refused = item
                    refused.refusal = "ouvert par \(who.sorted().joined(separator: ", ")) : ferme-le d’abord"
                    return refused
                }
            }.value
            convoyPhase = .confirmBatch(BatchPlan(action: action, items: items))
        }
    }

    /// Vérification d'un élément. Mêmes règles que les actions une par une.
    nonisolated static func check(_ location: (url: URL, title: String, bytes: Int64), for action: BatchAction,
                                  harbor: TargetVolume?, placement: Placement?, running: Set<String>, home: String) -> BatchItem {
        var item = BatchItem(url: location.url, title: location.title, bytes: location.bytes, targets: [location.url])
        switch action {
        case .trash:
            if Uninstaller.looksLikeApp(location.url) {
                do {
                    let plan = try Uninstaller().plan(for: location.url, running: running)
                    if let vendor = plan.vendorUninstaller {
                        item.refusal = "utilise son désinstalleur (« \(vendor.deletingPathExtension().lastPathComponent) »)"
                    } else {
                        item.targets = [plan.bundleLocation] + plan.leftovers.map(\.url)
                        item.note = (plan.leftovers.isEmpty ? "appli" : "appli + \(plan.leftovers.count) reste\(plan.leftovers.count > 1 ? "s" : "")")
                            + (plan.needsAdmin ? " · mot de passe" : "")
                    }
                } catch {
                    item.refusal = error.localizedDescription
                }
            } else if !Self.trashable(location.url, home: home) {
                let path = location.url.path
                item.refusal = path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/")
                    ? "données d’une appli, gérées par macOS : désinstalle l’appli pour les retirer avec elle"
                    : "géré par macOS, on n’y touche pas"
            }
        case .outremer:
            guard let harbor else { item.refusal = "aucun disque externe branché"; break }
            let verdict = MobilityJudge(target: harbor).judge(location.url)
            if verdict.mobility == .free || verdict.mobility == .withLink {
                // Rangement : la meilleure proposition (sans fusion en lot), sinon le dossier d'accueil.
                let suggestion = placement?.suggestions(for: location.url).first { !$0.merges }
                item.destination = suggestion?.folder.url
                item.note = "→ " + (suggestion?.folder.relativePath ?? "GoSaver Outre-mer")
            } else {
                item.refusal = verdict.reason
            }
        case .lazaret:
            guard let harbor else { item.refusal = "aucun disque externe branché"; break }
            let verdict = MobilityJudge(target: harbor).judge(location.url)
            if verdict.mobility == .forbidden, !Lazaret.onlyBlockedByMobilityConcerns(verdict) {
                item.refusal = verdict.reason
            } else if (verdict.contents?.symlinks ?? 0) > 0, !harbor.format.keepsSymlinks {
                item.refusal = "contient des liens que \(harbor.format.label) ne sait pas garder"
            }
        }
        return item
    }

    /// Même règle que le bouton « Mettre à la corbeille » de la fiche.
    nonisolated static func trashable(_ url: URL, home: String) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else { return false }
        let relative = String(path.dropFirst(home.count + 1))
        let protected = ["Library/Containers", "Library/Group Containers", "Library/Mobile Documents", "Library/Mail",
                         "Library/Messages", "Library/Keychains", "Library/Preferences", "Library/Photos", ".Trash"]
        return !protected.contains { relative == $0 || relative.hasPrefix($0 + "/") }
            && !["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library"].contains(relative)
    }

    // MARK: - Exécution

    func runBatch() {
        guard case .confirmBatch(let plan) = convoyPhase else { return }
        let ready = plan.ready
        guard !ready.isEmpty else { convoyPhase = .closed; return }
        convoyPhase = .running(stage: .copying, done: 0, total: plan.bytes, returning: false)

        switch plan.action {
        case .trash:
            let targets = ready.flatMap(\.targets)
            Task {
                let (gone, problem) = await recycle(targets)
                let done = ready.filter { gone.contains($0.url) }.map { (url: $0.url, bytes: $0.bytes) }
                let failed = ready.filter { !gone.contains($0.url) }
                    .map { "\($0.title) : \(problem ?? "refusé par macOS")" }
                finishBatch(plan, done: done, failures: failed + plan.refused.map { "\($0.title) : \($0.refusal ?? "")" })
            }
        case .outremer, .lazaret:
            guard let target = harborVolume else { convoyPhase = .failed("Aucun disque externe branché."); return }
            let lazaret = Lazaret(target: target, retention: Preferences.shared.lazaretRetention)
            Task {
                var done: [(url: URL, bytes: Int64)] = []
                var failures: [String] = plan.refused.map { "\($0.title) : \($0.refusal ?? "")" }
                for item in ready {
                    let result: Result<Int64, Error> = await Task.detached(priority: .userInitiated) {
                        Result {
                            plan.action == .outremer
                                ? try Convoy(target: target).send(item.url, into: item.destination).bytes
                                : try lazaret.quarantine(item.url).bytes
                        }
                    }.value
                    switch result {
                    case .success(let bytes):
                        done.append((item.url, bytes))
                        convoyPhase = .running(stage: .copying, done: done.reduce(0) { $0 + $1.bytes },
                                               total: plan.bytes, returning: false)
                    case .failure(let error):
                        failures.append("\(item.title) : \(error.localizedDescription)")
                    }
                }
                finishBatch(plan, done: done, failures: failures)
            }
        }
    }

    private func finishBatch(_ plan: BatchPlan, done: [(url: URL, bytes: Int64)], failures: [String]) {
        if let survey, !done.isEmpty { apply(.finished(survey.removing(done, volume: .of()))) }
        ruins.removeAll { ruin in done.contains { $0.url == ruin.url } }
        endSelection()
        selectedID = nil
        if !done.isEmpty { landRevision += 1 }
        refreshHarbor()
        let bytes = done.reduce(Int64(0)) { $0 + $1.bytes }
        let verb = switch plan.action {
        case .trash: "à la corbeille de macOS"
        case .outremer: "sur \(harborVolume?.name ?? "le disque externe")"
        case .lazaret: "au \(Words.lazaret)"
        }
        convoyPhase = .batchDone(title: "\(done.count) élément\(done.count > 1 ? "s" : "") \(verb)",
                                 bytes: bytes, failures: failures)
    }
}
