import OSLog

/// Journaux de l'appli, lisibles dans Console.app (sous-système fr.carlos.gosaver).
enum Log {
    static let map = Logger(subsystem: "fr.carlos.gosaver", category: "carte")
}
