import Foundation

/// Qui utilise un dossier en ce moment ?
///
/// Déplacer ou jeter un dossier pendant qu'un programme y écrit (une machine virtuelle UTM
/// allumée, une appli ouverte, une base de données) donnerait une copie incomplète ou corrompue.
/// On interroge donc `lsof` (« list open files » : la liste des fichiers ouverts par chaque
/// processus) avant toute opération, et on refuse tant que quelqu'un s'en sert.
public enum InUse {
    /// Processus du système qui ouvrent des fichiers quelques instants pour les indexer ou les
    /// sauvegarder : ils ne « tiennent » pas le dossier, inutile de bloquer pour eux.
    static let ignored: Set<String> = [
        "mds", "mds_stores", "mdworker", "mdworker_shared", "fseventsd", "backupd", "revisiond",
        "QuickLookUIService", "quicklookd", "lsof", "GoSaver", "Finder", "bird", "cloudd",
    ]

    /// Pour chaque dossier demandé, les noms des programmes qui y ont un fichier ouvert.
    /// Un dossier absent du résultat est libre. Bloquant (~1 s) : à appeler hors du fil principal.
    public static func holders(of urls: [URL]) -> [URL: Set<String>] {
        guard !urls.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -F cn : sortie lisible par une machine (nom du programme, chemin) ; +c 0 : noms complets ; -n -P : pas de
        // résolution réseau (plus rapide) ; -w : sans avertissements.
        process.arguments = ["-n", "-P", "-w", "+c", "0", "-F", "cn"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return match(String(decoding: data, as: UTF8.self), against: urls)
    }

    /// Lit la sortie de `lsof -F cn` et retrouve les dossiers concernés (testable sans lsof).
    static func match(_ listing: String, against urls: [URL]) -> [URL: Set<String>] {
        // Les deux écritures d'un même chemin : /var/… et /private/var/…, liens résolus ou non.
        let targets = urls.map { url -> (url: URL, prefixes: [String]) in
            let paths = Set([url.standardizedFileURL.path, url.resolvingSymlinksInPath().path,
                             "/private" + url.resolvingSymlinksInPath().path])
            return (url, paths.map { $0.hasSuffix("/") ? $0 : $0 + "/" })
        }
        var result: [URL: Set<String>] = [:]
        var command = ""
        for line in listing.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "c": command = value
            case "n":
                guard !ignored.contains(command), value.hasPrefix("/") else { continue }
                let path = value.hasSuffix("/") ? value : value + "/"
                for target in targets where target.prefixes.contains(where: { path.hasPrefix($0) }) {
                    result[target.url, default: []].insert(command)
                }
            default: continue
            }
        }
        return result
    }
}
