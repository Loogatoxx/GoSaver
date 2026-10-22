import SwiftUI
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

    func startSurvey() {
        guard phase != .surveying else { return }
        phase = .surveying
        selectedID = nil
        hoveredID = nil
        places = []
        survey = nil
        plannedPlaces = 0
        surveyedPlaces = 0
        task = Task {
            for await event in Surveyor().survey() {
                apply(event)
            }
        }
    }

    /// Applique un relevé déjà fait (mode instantané).
    func load(_ survey: Survey) {
        apply(.finished(survey))
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
