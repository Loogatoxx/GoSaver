import Foundation

/// Type de terrain sur la carte = grande famille de données.
/// Voir la table de correspondance dans docs/DESIGN_SYSTEM.md §1.
public enum Terrain: String, CaseIterable, Sendable, Codable {
    case massif   // macOS, système, données inaccessibles
    case city     // applications et leurs données
    case marsh    // caches et journaux
    case delta    // téléchargements
    case fields   // documents
    case forest   // photos, vidéos, musique
    case quarry   // outils de dev et leurs déblais
    case ruins    // fichiers mystères (rempli par l'enquête)
    case shore    // corbeille

    /// Nom de terrain, tel qu'il apparaît sur la carte.
    public var name: String {
        switch self {
        case .massif: "Massif"
        case .city:   "Cités"
        case .marsh:  "Marais"
        case .delta:  "Delta"
        case .fields: "Champs"
        case .forest: "Forêts"
        case .quarry: "Carrières"
        case .ruins:  "Ruines"
        case .shore:  "Grève"
        }
    }

    /// Ce que le terrain représente réellement : la donnée prime sur la métaphore.
    public var meaning: String {
        switch self {
        case .massif: "Système macOS"
        case .city:   "Applications"
        case .marsh:  "Caches et journaux"
        case .delta:  "Téléchargements"
        case .fields: "Documents"
        case .forest: "Photos, vidéos, musique"
        case .quarry: "Outils de développement"
        case .ruins:  "Fichiers d’origine inconnue"
        case .shore:  "Corbeille"
        }
    }

    /// Les données de ce terrain se reforment seules si on les supprime.
    public var regenerates: Bool {
        self == .marsh || self == .quarry
    }
}
