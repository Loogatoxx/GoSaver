import Foundation
import SwiftUI
import FoundationModels

/// L'IA locale (Apple Intelligence, modèle Foundation Models exécuté sur ce Mac).
///
/// Elle ne décide rien : le moteur de GoSaver a déjà établi les faits et ce qui est permis
/// (déplaçable ou non, appli ouverte, données gérées par macOS…). L'IA reçoit ces faits, explique
/// en langage courant de quoi il s'agit, et choisit un conseil **parmi les seules actions permises**.
/// L'utilisateur reste maître : c'est lui qui appuie sur le bouton.
/// Rien ne quitte le Mac : le modèle tourne hors ligne.
enum Advisor {
    struct Advice: Equatable {
        /// Ce qu'est ce dossier, en une phrase.
        let what: String
        /// Une des actions proposées.
        let choice: String
        let why: String
    }

    /// `nil` si l'IA est prête, sinon la raison lisible de son absence.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled):
            "Active Apple Intelligence dans Réglages Système pour obtenir un avis."
        case .unavailable(.modelNotReady):
            "Le modèle d’Apple Intelligence se télécharge encore. Réessaie dans quelques minutes."
        case .unavailable(.deviceNotEligible):
            "Ce Mac ne prend pas en charge Apple Intelligence."
        case .unavailable:
            "Apple Intelligence n’est pas disponible pour le moment."
        }
    }

    private static let instructions = """
    Tu aides à libérer de la place sur un Mac de 256 Go presque plein, avec un disque externe pour décharger. \
    Tu tutoies toujours : « tu », « ton », « tes » ; jamais « vous ». Français simple, phrases courtes, pas de jargon. \
    Tu t’appuies uniquement sur les faits donnés, surtout la ligne « Ce que GoSaver sait » ; tu n’inventes rien. \
    Règles : ce qui se recrée seul (caches, journaux, dépendances téléchargées) s’assèche ou part sans risque. \
    Ce qui est volumineux et rarement ouvert va sur le disque externe. \
    Un document, un projet ou des données personnelles ne se jettent jamais : on les garde ou on les déplace. \
    Le Lazaret est une corbeille du disque externe : récupérable pendant 30 jours, puis vidée. \
    « garder » seulement si l’élément sert souvent et qu’aucune autre option ne convient.
    """

    /// Demande un avis sur un élément. `facts` : ce que GoSaver sait ; `choices` : les actions permises.
    static func advise(facts: String, choices: [String]) async throws -> Advice {
        let schema = try GenerationSchema(root: DynamicGenerationSchema(name: "Avis", properties: [
            // L'ordre compte : le modèle écrit d'abord ce qu'il comprend et son raisonnement,
            // puis choisit ; choisir en premier le pousse à justifier après coup un choix hâtif.
            .init(name: "quoi", description: "À quoi sert cet élément, en une phrase simple (pas seulement son nom)",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "pourquoi", description: "Le raisonnement, en une ou deux phrases, en tutoyant, d’après « Ce que GoSaver sait » et « Conseil de GoSaver »",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "conseil", description: "L’action qui découle du raisonnement",
                  schema: DynamicGenerationSchema(name: "Conseil", anyOf: choices)),
        ]), dependencies: [])
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: facts, schema: schema,
                                                 options: GenerationOptions(sampling: .greedy))
        let content = response.content
        return Advice(what: try content.value(String.self, forProperty: "quoi"),
                      choice: try content.value(String.self, forProperty: "conseil"),
                      why: try content.value(String.self, forProperty: "pourquoi"))
    }

    /// Dernière ouverture connue de Spotlight, si macOS l'a notée.
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

/// Section « Avis du cartographe » d'une fiche : un bouton, puis l'avis et sa provenance.
struct AdviceSection: View {
    /// Faits et actions permises, calculés au moment de la demande.
    let ask: () -> (facts: String, choices: [String])
    @State private var state: Phase = .idle

    private enum Phase: Equatable {
        case idle, thinking
        case done(Advisor.Advice)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(Words.atlas ? "Avis du cartographe" : "Avis de l’IA").regionStyle().foregroundStyle(Ink.inkFaded)
            switch state {
            case .idle:
                if let reason = Advisor.unavailableReason {
                    Text(reason).font(Typo.label).foregroundStyle(Ink.inkFaded)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button("Demander un avis") { run() }.buttonStyle(NoteButtonStyle())
                }
            case .thinking:
                Text(Words.atlas ? "Le cartographe examine le lieu…" : "Analyse en cours…")
                    .font(Typo.water).foregroundStyle(Ink.inkFaded)
            case .done(let advice):
                Text(advice.what).font(Typo.body).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("Conseil").font(Typo.label).foregroundStyle(Ink.inkFaded)
                    Text(advice.choice.uppercased()).font(Typo.region).tracking(Typo.regionTracking)
                        .foregroundStyle(Ink.sea)
                }
                Text(advice.why).font(Typo.water).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Avis généré sur ce Mac par Apple Intelligence, qui peut se tromper. La décision reste la tienne.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message).font(Typo.label).foregroundStyle(Ink.ochre)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { run() }.buttonStyle(NoteButtonStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func run() {
        let (facts, choices) = ask()
        state = .thinking
        Task {
            do {
                state = .done(try await Advisor.advise(facts: facts, choices: choices))
            } catch {
                Log.map.error("Avis IA : \(error.localizedDescription, privacy: .public)")
                state = .failed("L’IA n’a pas pu répondre (\(error.localizedDescription)).")
            }
        }
    }
}
