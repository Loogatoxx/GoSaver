# GoSaver — Feuille de route

> Mise à jour : 2026-10-22

## Fait

| Étape | Contenu |
|---|---|
| Fondations | Charte « Atlas », jetons Swift, polices, `bundle.sh`, mode `--snapshot` |
| Relevé | Moteur parallèle en lecture seule (~10 s pour tout le disque), zones, enclaves, Registre |
| Carte 3D | Géographie proportionnelle, limite du disque, impression gravée, plan-relief RealityKit, brouillard, caméra en orbite bornée |
| Interaction | Visée à la souris, jalon, vol de caméra, fiche de lieu, sélection partagée avec le Registre |
| Assèchement | Caches, journaux et corbeille (sur demande) ; liste blanche, revérification des chemins, applis ouvertes épargnées ; érosion animée |

## À venir (dans l'ordre)

1. **Accès complet au disque** : écran d'explication et lien vers Réglages, relevé des zones aujourd'hui refusées.
2. **Déplaçabilité** (voir ci-dessous), puis **Outre-mer** : migration vers le Lexar, convois animés, rapatriement.
3. **Lazaret** : enquête sur les fichiers mystères, quarantaine de 30 jours, suppression automatique.
4. **IA locale** (Foundation Models) : propositions de rangement et explications, toujours validées par l'utilisateur.
5. **Sons** (synthèse modale) et passes `/design-critique`, `/accessibility-review`, `/ux-copy`.
6. Après l'appli : aide au rangement du Lexar.

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
