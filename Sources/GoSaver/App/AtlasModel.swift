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
        let bytes: Int64
        let places: [Place]
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
                singles.append(Landmark(id: place.id, title: PlaceNames.display(place), bytes: place.bytes, places: [place]))
            }
        }
        for (kind, members) in groups {
            let total = members.reduce(Int64(0)) { $0 + $1.bytes }
            let title = members.count == 1 ? PlaceNames.display(members[0]) : "\(kind) × \(members.count)"
            singles.append(Landmark(id: "enclave:" + kind, title: title, bytes: total, places: members))
        }
        return singles.sorted { $0.bytes > $1.bytes }
    }

    /// Genre d'enclave (« node_modules », « Caches ») si le lieu en est une.
    private static func enclaveKind(_ place: Place) -> String? {
        guard place.isEnclave, let dash = place.name.range(of: " — ") else { return nil }
        return String(place.name[..<dash.lowerBound])
    }

    private var task: Task<Void, Never>?

    func startSurvey() {
        guard phase != .surveying else { return }
        phase = .surveying
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
        for place in survey.places { apply(.surveyed(place)) }
        apply(.finished(survey))
    }

    private func apply(_ event: SurveyEvent) {
        switch event {
        case .planned(let count):
            plannedPlaces = count
        case .progress(let files, let bytes):
            filesSoFar = files
            bytesSoFar = bytes
        case .surveyed(let place):
            surveyedPlaces += 1
            places.append(place)
        case .finished(let result):
            survey = result
            volume = result.volume
            places = result.places
            surveyedPlaces = plannedPlaces
            phase = .surveyed
        }
    }
}
