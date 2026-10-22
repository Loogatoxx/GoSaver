import Foundation

/// Le disque de destination d'un déplacement (l'« Outre-mer »), et ce que son format sait conserver.
public struct TargetVolume: Sendable, Equatable {
    public enum Format: String, Sendable {
        case apfs, hfs, exfat, fat, other

        public var label: String {
            switch self {
            case .apfs: "APFS"
            case .hfs: "Mac OS étendu"
            case .exfat: "exFAT"
            case .fat: "FAT32"
            case .other: "format inconnu"
            }
        }

        /// Garde les liens symboliques à l'intérieur des dossiers.
        public var keepsSymlinks: Bool { self == .apfs || self == .hfs }
        /// Garde propriétaires, droits d'exécution et attributs étendus (signature des applis…).
        public var keepsPermissions: Bool { self == .apfs || self == .hfs }
        /// Sait stocker un fichier « creux » sans le gonfler.
        public var keepsSparseFiles: Bool { self == .apfs }
        /// Taille maximale d'un fichier (FAT32 : 4 Go moins un octet).
        public var maxFileSize: Int64? { self == .fat ? 4_294_967_295 : nil }
    }

    public let url: URL
    public let name: String
    public let format: Format
    public let freeBytes: Int64

    public init(url: URL, name: String, format: Format, freeBytes: Int64) {
        self.url = url; self.name = name; self.format = format; self.freeBytes = freeBytes
    }

    /// Décrit le volume monté à cet emplacement (lit le type de système de fichiers via `statfs`).
    public static func detect(_ url: URL) -> TargetVolume? {
        var stats = statfs()
        guard statfs(url.path, &stats) == 0 else { return nil }
        let type = withUnsafeBytes(of: stats.f_fstypename) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let format: Format = switch type {
        case "apfs": .apfs
        case "hfs": .hfs
        case "exfat": .exfat
        case "msdos": .fat
        default: .other
        }
        let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeAvailableCapacityKey])
        return TargetVolume(url: url, name: values?.volumeLocalizedName ?? url.lastPathComponent,
                            format: format, freeBytes: Int64(values?.volumeAvailableCapacity ?? 0))
    }

    /// Disques externes actuellement branchés (ni le disque de démarrage, ni les volumes système).
    public static func externalVolumes() -> [TargetVolume] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            guard v?.volumeIsRootFileSystem != true, v?.volumeIsInternal != true, v?.volumeIsBrowsable != false
            else { return nil }
            return detect(url)
        }
    }
}
