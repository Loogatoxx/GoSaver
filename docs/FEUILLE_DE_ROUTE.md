# GoSaver — Feuille de route

> Mise à jour : 2026-10-22

## Fait

| Étape | Contenu |
|---|---|
| Fondations | Charte « Atlas », jetons Swift, polices, `bundle.sh`, mode `--snapshot` |
| Relevé | Moteur parallèle en lecture seule (~10 s pour tout le disque), zones, enclaves, Registre |
| Carte 3D | Géographie proportionnelle, limite du disque, impression gravée, plan-relief RealityKit, brouillard, caméra en orbite bornée |
| Interaction | Visée à la souris, jalon, vol de caméra, fiche de lieu, sélection partagée avec le Registre |
| Accès complet au disque | Détection par dossiers témoins, feuille en trois étapes, revérification au retour dans l'appli, relance |
| Signature stable | Certificat local « GoSaver Dev » : même identité d'une compilation à l'autre, l'accès complet au disque est conservé |
| Déplaçabilité | `MobilityJudge` : verdict Libre / Avec lien / Déconseillé / Interdit + raison + conseil, d'après l'emplacement, le contenu (liens, programmes, git, iCloud, fichiers creux) et le disque cible (format, place) ; affiché dans la fiche de lieu |
| Outre-mer | Convoi « copier, vérifier, remplacer » (empreintes début/fin), lien symbolique si nécessaire, registre de bord sur le disque, rapatriement ; feuille d'envoi, section Outre-mer du Registre |
| Rangement outre-mer | Index des dossiers du disque, 3 propositions expliquées (contenu, nom, profondeur), fusion dans un dossier du même nom sans rien écraser, choix manuel, reclassement des envois |
| Lazaret | Corbeille du disque externe : « Mettre au Lazaret » depuis la fiche, rangé par jour, restaurable 30 jours puis supprimé automatiquement (à l'ouverture de GoSaver, disque branché) ; système, bac à sable et iCloud refusés |
| Ruines | Expertise : données d'applis disparues, doublons exacts, installeurs déjà utilisés, téléchargements interrompus, fichiers d'origine inconnue (contenu réel, provenance, appli, dernière ouverture) ; fiche d'expertise à tampon ; isolement au Lazaret, un par un ou en lot |
| Réglages | Langage Atlas/Classique, apparence, animations réduites, relevé au lancement, dossiers exclus, corbeille par défaut, disque de destination, durée du Lazaret, délai « appli disparue », isolement automatique des ruines, accès, réinitialisation |
| Désinstalleur | Appli + restes portant exactement son identifiant ou son nom, à la corbeille de macOS ; refus pour applis ouvertes et applis d'Apple ; désinstalleur de l'éditeur proposé en premier |
| Corbeille et Registre complet | « Mettre à la corbeille » pour les fichiers de l'utilisateur ; « et N autres lieux » se déplie par 50 |
| Carrières | Dossiers `build/` de projets (Flutter, Android, CMake, Swift) et `.dart_tool` reconnus |
| Convoi animé | Route pointillée vermillon et navire qui avance au rythme de la copie vers l'Outre-mer |
| Icône | Île gravée, courbes de niveau, jalon vermillon, cadre de carte (`scripts/make-icon.sh`) |
| Assèchement | Caches, journaux et corbeille (sur demande) ; liste blanche, revérification des chemins, applis ouvertes épargnées ; érosion animée |

## À venir (dans l'ordre)

Abandonné à la demande de l'utilisateur (2026-10-23) : les sons.

Fait le 2026-10-23 : passes de finition (critique, accessibilité, rédaction), sécurité (refus des dossiers ouverts via `lsof`, alerte des liens rompus quand le disque est débranché), IA locale (avis Foundation Models dans les fiches, choisi parmi les seules actions permises).

1. **Rangement final** (demandé au départ) : organiser le Mac et le Lexar (cours par matière et par date, jeux et projets regroupés), y compris les 3 machines virtuelles UTM (~29 Go) vers le Lexar, à la manière d'UTM (machine éteinte, réouverture depuis le Lexar).

---

## Déplaçabilité — ce qui peut partir sur le SSD

**Principe : c'est le moteur qui décide, l'IA qui explique.** Savoir si un dossier peut être déplacé sans rien casser est une question de règles vérifiables (format du disque, signature de code, fichiers ouverts…), pas de devinette. Une IA de cette taille peut se tromper ; une règle, non. Le moteur rend donc un verdict avec sa raison, et l'IA s'en sert pour formuler sa proposition. Elle ne peut jamais proposer de déplacer ce que le moteur interdit.

### Verdicts

| Verdict | Sens | Exemples |
|---|---|---|
| **Libre** | Se déplace tel quel, rien ne le cherche à cet endroit | Documents, vidéos, archives, ISO, anciens projets, téléchargements |
| **Avec lien** | Une appli l'attend à cet endroit : on déplace et on laisse un lien symbolique | Machines virtuelles UTM, sauvegardes iPhone, SDK Android, caches Gradle |
| **Déconseillé** | Possible, mais avec un effet de bord à expliquer | Applis de `/Applications` (mises à jour cassées), jeux Steam (à déplacer depuis Steam) |
| **Interdit** | Ne doit jamais partir | Système, `~/Library` hors exceptions listées, bibliothèque Photos sur exFAT, conteneurs d'applis sandboxées |

### Règles vérifiées par le moteur

- **Format du disque cible.** L'exFAT ne garde ni permissions Unix, ni attributs étendus, ni liens symboliques internes. Il refuse donc les bundles signés (applis), les bibliothèques Photos/Musique, et tout dossier contenant des liens symboliques.
- **Fichiers creux.** Un disque de machine virtuelle annonce par exemple 64 Go, mais n'occupe que la place réellement remplie. L'exFAT ne gère pas ce format, la copie risque donc de gonfler. On compare la taille logique à la taille allouée, et on prévient si la place manque sur le SSD.
- **Fichiers ouverts.** On refuse si une appli utilise le dossier au moment du déplacement.
- **iCloud.** Un fichier « dans le nuage » (non téléchargé) n'est pas déplacé.
- **Conteneurs sandboxés** (`~/Library/Containers`). Interdits : macOS les protège et les recrée.
- **SSD débranché.** Un dossier « avec lien » devient inaccessible, l'appli concernée est prévenue à la reconnexion. Le rapatriement est toujours proposé.

---

## Signature de développement

`scripts/bundle.sh` signe avec le certificat « GoSaver Dev » s'il est dans le trousseau, sinon en ad hoc.

- Vérifier : `security find-identity -p codesigning` (la mention `CSSMERR_TP_NOT_TRUSTED` est normale : certificat local, non validé par une autorité).
- Identité reconnue par macOS : `codesign -d -r- build/GoSaver.app` → `identifier "fr.carlos.gosaver" and certificate root = H"cbc74d8f…"`.
- Supprimer le certificat : `security delete-identity -c "GoSaver Dev"`.
- Le certificat ne sert qu'à ce Mac : il ne permet pas de distribuer l'appli à d'autres (il faudrait un compte développeur Apple et la notarisation).

