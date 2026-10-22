import Foundation
import UniformTypeIdentifiers

/// Les indices relevés sur un fichier ou un dossier dont on ignore l'origine.
/// Tout vient de ce que macOS sait déjà : type, attributs étendus, dates, métadonnées Spotlight.
/// Rien n'est envoyé nulle part.
public struct Clues: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
    /// Ce que le contenu est vraiment (lu dans les premiers octets), quand l'extension est trompeuse.
    public let content: String?
    /// Description du type selon macOS (« Image disque », « Document Microsoft Word »…).
    public let typeDescription: String?
    /// Site d'où il a été téléchargé (attribut « provenance » que macOS ajoute aux téléchargements).
    public let downloadedFrom: String?
    /// Appli qui l'a téléchargé (attribut de quarantaine de macOS).
    public let downloadedBy: String?
    public let created: Date?
    public let modified: Date?
    /// Dernière ouverture connue de Spotlight (`nil` : jamais ouvert, ou inconnu).
    public let lastOpened: Date?

    /// Relève les indices (lecture seule).
    public static func gather(_ url: URL) -> Clues {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let quarantine = xattrString(url, "com.apple.quarantine")
        // Format : « drapeaux;horodatage;appli;identifiant ».
        let agent = quarantine?.split(separator: ";", omittingEmptySubsequences: false).dropFirst(2).first
            .map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let metadata = NSMetadataItem(url: url)
        return Clues(
            url: url,
            bytes: Drainer.allocatedSize(of: url),
            content: isDirectory ? nil : sniff(url),
            typeDescription: isDirectory ? nil : UTType(filenameExtension: url.pathExtension)?.localizedDescription,
            downloadedFrom: whereFrom(url),
            downloadedBy: agent,
            created: values?.creationDate,
            modified: values?.contentModificationDate,
            lastOpened: metadata?.value(forAttribute: "kMDItemLastUsedDate") as? Date
        )
    }

    // MARK: - Lecture des attributs étendus

    static func xattrData(_ url: URL, _ name: String) -> Data? {
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read > 0 ? data.prefix(read) : nil
    }

    static func xattrString(_ url: URL, _ name: String) -> String? {
        xattrData(url, name).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Provenance : liste plist d'adresses ; on garde le nom du site de la première.
    static func whereFrom(_ url: URL) -> String? {
        guard let data = xattrData(url, "com.apple.metadata:kMDItemWhereFroms"),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
              let first = list.first(where: { $0.hasPrefix("http") }) ?? list.first
        else { return nil }
        return URL(string: first)?.host()?.replacingOccurrences(of: "www.", with: "") ?? first
    }

    // MARK: - Lecture du contenu

    /// Identifie le contenu par ses premiers octets (« nombre magique »), indépendamment de l'extension.
    /// Exemple : un « .ts » peut être une vidéo (MPEG-TS) ou du code TypeScript.
    static func sniff(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 1024), !head.isEmpty else { return "fichier vide" }
        let b = [UInt8](head)
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + prefix.count && Array(b[offset..<offset + prefix.count]) == prefix
        }
        // MPEG-TS : un octet de synchronisation 0x47 tous les 188 octets.
        if b.count > 376, b[0] == 0x47, b[188] == 0x47, b[376] == 0x47 { return "vidéo (flux MPEG-TS)" }
        if starts(Array("%PDF".utf8)) { return "document PDF" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "archive ZIP (ou document Office)" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "image PNG" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image JPEG" }
        if starts(Array("ftyp".utf8), at: 4) { return "vidéo ou audio (MP4/MOV)" }
        if starts(Array("ID3".utf8)) { return "musique MP3" }
        if starts(Array("RIFF".utf8)) { return "audio ou vidéo (RIFF)" }
        if starts([0xCF, 0xFA, 0xED, 0xFE]) || starts([0xCA, 0xFE, 0xBA, 0xBE]) { return "programme macOS" }
        if starts(Array("MZ".utf8)) { return "programme Windows" }
        if starts(Array("koly".utf8)) || url.pathExtension.lowercased() == "dmg" { return "image disque" }
        if starts([0x1F, 0x8B]) { return "archive compressée (gzip)" }
        if starts(Array("7z".utf8)) { return "archive 7-Zip" }
        if starts(Array("Rar!".utf8)) { return "archive RAR" }
        if starts(Array("SQLite format".utf8)) { return "base de données SQLite" }
        if String(data: head, encoding: .utf8) != nil {
            let text = String(decoding: head, as: UTF8.self)
            if text.hasPrefix("#!") { return "script" }
            if text.contains("function") || text.contains("import ") || text.contains("const ") { return "code source (texte)" }
            return "texte"
        }
        return nil
    }
}
