import SwiftUI
import GoSaverCore

/// Les réglages de GoSaver, enregistrés dans les préférences macOS (UserDefaults).
/// `@Observable` : toute vue qui lit un réglage se redessine quand il change.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    enum Appearance: String, CaseIterable, Identifiable {
        case system, paper, lamp
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "Comme le système"
            case .paper: "Papier (clair)"
            case .lamp: "Lampe (sombre)"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .paper: .light
            case .lamp: .dark
            }
        }
    }

    private let defaults = UserDefaults.standard

    /// Langage d'exploration (Marais, Carrières, Lazaret…) ou langage classique (Caches, Outils de dev…).
    var explorationLanguage: Bool { didSet { defaults.set(explorationLanguage, forKey: "langageExploration") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "apparence") } }
    /// Animations réduites même si le réglage d'accessibilité de macOS ne l'est pas.
    var reducedAnimations: Bool { didSet { defaults.set(reducedAnimations, forKey: "animationsReduites") } }
    var surveyOnLaunch: Bool { didSet { defaults.set(surveyOnLaunch, forKey: "releveAuLancement") } }
    /// Dossiers exclus du relevé.
    var excludedFolders: [String] { didSet { defaults.set(excludedFolders, forKey: "dossiersExclus") } }
    /// Case « corbeille » cochée d'office dans l'assèchement.
    var trashCheckedByDefault: Bool { didSet { defaults.set(trashCheckedByDefault, forKey: "corbeilleParDefaut") } }
    /// Disque externe choisi (chemin de montage) ; vide : le premier branché.
    var harborPath: String { didSet { defaults.set(harborPath, forKey: "disqueExterne") } }
    var lazaretDays: Int { didSet { defaults.set(lazaretDays, forKey: "dureeLazaret") } }
    var orphanDays: Int { didSet { defaults.set(orphanDays, forKey: "delaiApplisDisparues") } }
    /// Mettre au Lazaret, sans demander, les ruines sûres trouvées après chaque relevé.
    var autoIsolateRuins: Bool { didSet { defaults.set(autoIsolateRuins, forKey: "isolementAutomatique") } }

    private init() {
        defaults.register(defaults: [
            "langageExploration": true, "apparence": Appearance.system.rawValue, "animationsReduites": false,
            "releveAuLancement": false, "corbeilleParDefaut": false, "disqueExterne": "",
            "dureeLazaret": 30, "delaiApplisDisparues": 90, "isolementAutomatique": false,
        ])
        explorationLanguage = defaults.bool(forKey: "langageExploration")
        appearance = Appearance(rawValue: defaults.string(forKey: "apparence") ?? "") ?? .system
        reducedAnimations = defaults.bool(forKey: "animationsReduites")
        surveyOnLaunch = defaults.bool(forKey: "releveAuLancement")
        excludedFolders = defaults.stringArray(forKey: "dossiersExclus") ?? []
        trashCheckedByDefault = defaults.bool(forKey: "corbeilleParDefaut")
        harborPath = defaults.string(forKey: "disqueExterne") ?? ""
        lazaretDays = defaults.integer(forKey: "dureeLazaret")
        orphanDays = defaults.integer(forKey: "delaiApplisDisparues")
        autoIsolateRuins = defaults.bool(forKey: "isolementAutomatique")
    }

    var lazaretRetention: TimeInterval { TimeInterval(lazaretDays) * 86_400 }
    var excludedURLs: [URL] { excludedFolders.map { URL(fileURLWithPath: $0) } }

    /// Remet tout comme au premier lancement.
    func reset() {
        for key in ["langageExploration", "apparence", "animationsReduites", "releveAuLancement", "dossiersExclus",
                    "corbeilleParDefaut", "disqueExterne", "dureeLazaret", "delaiApplisDisparues", "isolementAutomatique"] {
            defaults.removeObject(forKey: key)
        }
        explorationLanguage = true; appearance = .system; reducedAnimations = false; surveyOnLaunch = false
        excludedFolders = []; trashCheckedByDefault = false; harborPath = ""; lazaretDays = 30; orphanDays = 90
        autoIsolateRuins = false
    }
}

/// Le lexique : chaque mot de l'interface en deux voix. L'Atlas raconte une exploration ;
/// le Classique dit les choses telles quelles. Les chiffres et les verdicts ne changent jamais.
@MainActor
enum Words {
    static var atlas: Bool { Preferences.shared.explorationLanguage }

    static func terrain(_ t: Terrain) -> String {
        guard !atlas else { return t.name }
        switch t {
        case .massif: return "Système"
        case .city: return "Applications"
        case .marsh: return "Caches"
        case .delta: return "Téléchargements"
        case .fields: return "Documents"
        case .forest: return "Médias"
        case .quarry: return "Outils de dev"
        case .ruins: return "Restes"
        case .shore: return "Corbeille"
        }
    }

    /// Sous-titre d'un terrain : en Atlas, ce qu'il représente ; en Classique, une précision.
    static func terrainDetail(_ t: Terrain) -> String {
        guard !atlas else { return t.meaning }
        switch t {
        case .massif: return "macOS et zones non analysées"
        case .city: return "et leurs données"
        case .marsh: return "et journaux"
        case .delta: return "fichiers récupérés du web"
        case .fields: return "tes fichiers"
        case .forest: return "photos, vidéos, musique"
        case .quarry: return "SDK, dépendances, caches de compilation"
        case .ruins: return "fichiers inutiles ou d’origine inconnue"
        case .shore: return "éléments supprimés"
        }
    }

    static var ledger: String { atlas ? "Registre" : "Détail" }
    static var survey: String { atlas ? "relevé" : "analyse" }
    static var startSurvey: String { atlas ? "Lancer le relevé" : "Lancer l’analyse" }
    static var redoSurvey: String { atlas ? "Refaire le relevé" : "Refaire l’analyse" }
    static var surveyDone: String { atlas ? "Relevé terminé" : "Analyse terminée" }
    static var surveying: String { atlas ? "Relevé en cours" : "Analyse en cours" }
    static var mapTitle: String { atlas ? "Atlas du disque" : "Espace disque" }
    static var freeSea: String { atlas ? "de mer libre" : "libres" }
    static var drain: String { atlas ? "Assécher les marais" : "Nettoyer les caches" }
    static var outremer: String { atlas ? "Outre-mer" : "Disque externe" }
    static var sendOutremer: String { atlas ? "Envoyer outre-mer" : "Déplacer vers le disque externe" }
    static var lazaret: String { atlas ? "Lazaret" : "Corbeille du disque externe" }
    static var toLazaret: String { atlas ? "Mettre au Lazaret" : "Mettre à la corbeille du disque" }
    /// Ce que l'assèchement a libéré.
    static var reclaimed: String { atlas ? "rendus à la mer" : "libérés" }
    /// Ce qui reste invisible sans l'accès complet au disque.
    static var hiddenWithoutAccess: String {
        atlas ? "Sans l’accès complet au disque, la corbeille et certains dossiers restent dans le brouillard."
              : "Sans l’accès complet au disque, la corbeille et certains dossiers ne sont pas analysés."
    }
    static var closedZones: String { atlas ? "Zones fermées" : "Dossiers protégés" }

    static var idleLine: String {
        atlas ? "de mer libre autour de l’île. Le relevé n’a pas encore commencé."
              : "d’espace libre. L’analyse n’a pas encore commencé."
    }
    static var surveyedLine: String {
        atlas ? "de marais et de grève à assécher sans risque : ils se reforment seuls ou sont déjà à la corbeille."
              : "de caches et de corbeille à nettoyer sans risque : ils se recréent seuls ou sont déjà supprimés."
    }
    static func surveyingLine(_ done: Int, _ planned: Int) -> String {
        atlas ? "relevés dans \(done) lieux sur \(planned). Le brouillard se lève."
              : "analysés dans \(done) dossiers sur \(planned)."
    }
}
