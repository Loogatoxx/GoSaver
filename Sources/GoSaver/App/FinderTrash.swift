import Foundation

/// Mise à la corbeille par le Finder, pour ce que GoSaver n'a pas le droit de déplacer seul
/// (applis installées par l'administrateur, comme la plupart de celles de /Applications).
///
/// C'est exactement ce qui se passe quand on glisse l'élément vers la corbeille : le Finder
/// affiche lui-même la demande de mot de passe administrateur. GoSaver ne voit jamais le mot de passe.
/// La première fois, macOS demande d'autoriser GoSaver à « contrôler le Finder » (Automatisation).
enum FinderTrash {
    enum Outcome: Equatable {
        case done
        case cancelled
        case notAllowed
        case failed(String)

        var message: String? {
            switch self {
            case .done: nil
            case .cancelled: "Demande de mot de passe annulée : rien n’a été supprimé."
            case .notAllowed: "GoSaver n’a pas le droit de demander au Finder. Autorise-le dans Réglages Système › Confidentialité et sécurité › Automatisation › GoSaver › Finder."
            case .failed(let why): why
            }
        }
    }

    /// Demande au Finder de mettre ces éléments à la corbeille. Bloquant : à appeler hors du fil principal.
    static func trash(_ urls: [URL]) -> Outcome {
        guard !urls.isEmpty else { return .done }
        // Les chemins passent en arguments (« argv ») : aucun risque avec les apostrophes ou les guillemets.
        let script = [
            "on run argv",
            "  set targets to {}",
            "  repeat with p in argv",
            "    set end of targets to (POSIX file (p as text) as alias)",
            "  end repeat",
            "  tell application \"Finder\" to delete targets",
            "end run",
        ]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = script.flatMap { ["-e", $0] } + urls.map(\.path)
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return .failed(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return .done }
        let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if text.contains("-128") { return .cancelled }
        if text.contains("-1743") || text.contains("-10004") { return .notAllowed }
        return .failed(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
