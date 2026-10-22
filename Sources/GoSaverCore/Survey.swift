import Foundation

/// Un lieu de la carte : un dossier (ou un regroupement) relevé, avec sa taille réelle.
public struct Place: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let zone: String
    public let terrain: Terrain
    /// Octets réellement occupés sur le disque (blocs alloués, pas la taille « logique »).
    public let bytes: Int64
    public let fileCount: Int
    /// Les plus gros fichiers du lieu, du plus gros au plus petit.
    public let largestFiles: [FileItem]
    /// Vrai pour une enclave (node_modules, Library/Caches d'une appli…) trouvée dans un lieu.
    public var isEnclave = false

    /// Le même lieu, rangé dans un autre terrain (ex. des données d'appli disparue → Ruines).
    public func with(terrain: Terrain) -> Place {
        Place(url: url, name: name, zone: zone, terrain: terrain, bytes: bytes, fileCount: fileCount,
              largestFiles: largestFiles, isEnclave: isEnclave)
    }
}

public struct FileItem: Sendable, Hashable {
    public let url: URL
    public let bytes: Int64
}

/// Capacité et occupation d'un volume, comme les affiche le Finder.
public struct VolumeInfo: Sendable {
    public let name: String
    public let capacity: Int64
    public let used: Int64
    public var free: Int64 { capacity - used }

    public static func of(_ url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo {
        let values = try? url.resourceValues(forKeys: [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        let capacity = Int64(values?.volumeTotalCapacity ?? 0)
        // « Important usage » inclut l'espace purgeable que macOS libère à la demande :
        // c'est le chiffre « disponible » du Finder.
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return VolumeInfo(name: values?.volumeLocalizedName ?? "Macintosh HD",
                          capacity: capacity, used: max(0, capacity - available))
    }
}

/// Résultat complet d'un relevé.
public struct Survey: Sendable {
    public let volume: VolumeInfo
    public let places: [Place]
    /// Dossiers que macOS a refusé d'ouvrir (accès complet au disque manquant).
    public let deniedPaths: [String]
    public let duration: Duration

    public init(volume: VolumeInfo, places: [Place], deniedPaths: [String], duration: Duration) {
        self.volume = volume
        self.places = places
        self.deniedPaths = deniedPaths
        self.duration = duration
    }

    /// Le même relevé après suppression d'éléments : chaque lieu qui les contenait
    /// est allégé d'autant, et le volume est relu.
    public func removing(_ removed: [(url: URL, bytes: Int64)], volume newVolume: VolumeInfo) -> Survey {
        let updated = places.compactMap { place -> Place? in
            let base = place.url.path
            let lost = removed.reduce(Int64(0)) { sum, item in
                let path = item.url.path
                return path == base || path.hasPrefix(base + "/") ? sum + item.bytes : sum
            }
            guard lost > 0 else { return place }
            let bytes = max(0, place.bytes - lost)
            guard bytes > 0 else { return nil }
            return Place(url: place.url, name: place.name, zone: place.zone, terrain: place.terrain,
                         bytes: bytes, fileCount: place.fileCount, largestFiles: place.largestFiles.filter { file in
                             !removed.contains { file.url.path == $0.url.path || file.url.path.hasPrefix($0.url.path + "/") }
                         }, isEnclave: place.isEnclave)
        }
        return Survey(volume: newVolume, places: updated, deniedPaths: deniedPaths, duration: duration)
    }

    public var surveyedBytes: Int64 { places.reduce(0) { $0 + $1.bytes } }

    /// Ce qui n'a pas été relevé : système scellé, instantanés APFS, zones protégées.
    public var massifBytes: Int64 { max(0, volume.used - surveyedBytes) }

    public func bytes(of terrain: Terrain) -> Int64 {
        terrain == .massif
            ? massifBytes
            : places.lazy.filter { $0.terrain == terrain }.reduce(0) { $0 + $1.bytes }
    }
}

/// Ce que le relevé raconte pendant qu'il avance (pour lever le brouillard en direct).
public enum SurveyEvent: Sendable {
    /// Nombre de lieux à relever, connu au départ.
    case planned(places: Int)
    /// Cumul en cours.
    case progress(files: Int, bytes: Int64)
    /// Un lieu vient d'être entièrement relevé.
    case surveyed(Place)
    case finished(Survey)
}
