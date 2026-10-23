# Historique des prompts — GoSaver

## 2026-10-21 — Cadrage du projet (/grill-me)

**Prompt :** « Fais une appli pour Mac, le but est de faire comme CleanMyMac sur le système de gestion de stockage… quelque chose de stylé et pas IA… animations et bruits pour que ce soit immersif. » Suivi de 9 réponses de cadrage.

**Réponse :** série de questions pour fixer le besoin réel, puis récapitulatif validé.

**Modifications :** aucune (cadrage uniquement).

**Objectif :** décider avant de coder. Décisions actées :
- Outil réel pour le Mac 256 Go (≈ 33 Go libres), pas une démo.
- Migration vers le SSD Lexar (exFAT) : déplacement de fichiers + liens symboliques en option avancée.
- Swift/SwiftUI natif, compilé avec Swift Package Manager (sans Xcode, pour économiser 12–15 Go).
- IA locale Apple Foundation Models, uniquement conseillère.
- Fichiers « mystères » : enquête automatique → Quarantaine 30 jours → suppression automatique.
- Direction artistique : atlas topographique 3D (RealityKit), exploration façon jeu (brouillard, ruines, convoi vers le SSD).
- Sons par synthèse modale (sons physiques, pas de 8-bit).
- Nom : **GoSaver** (Go = gigaoctet, Saver = sauveur).

## 2026-10-21 — Initialisation

**Prompt :** « Je valide… GoSaver ou GoSave, tu choisis. » + choix : dépôt GitHub privé, code dans `~/Developer/GoSaver`.

**Réponse :** nom GoSaver retenu ; dossier sur le disque interne car l'exFAT du Lexar casse la signature de code.

**Modifications :** `git init`, `.gitignore` (build, secrets, fichiers `._` macOS), dépôt privé `Loogatoxx/GoSaver` créé (aucun push), ce fichier.

**Objectif :** poser une base propre et traçable avant la charte graphique.

## 2026-10-21 — Charte graphique et squelette

**Prompt :** (suite de la validation) lancer le projet.

**Réponse :** charte « Atlas » rédigée, contrastes vérifiés par calcul, squelette Swift compilé et rendu vérifié en clair et en sombre.

**Modifications :**
- `docs/DESIGN_SYSTEM.md` : métaphore complète (île, mer = espace libre, relief = taille, brouillard, Lazaret = quarantaine, Outre-mer = SSD), liste noire, encres Papier/Lampe, typographie, traits, composants, mouvement, sons.
- Encres `vermilion` et `ochre` foncées pour passer WCAG AA sur tous les fonds.
- `Package.swift` (macOS 26, SwiftPM), `Sources/GoSaver/Design/` (Palette, Typography, Metrics, Cartouche, ScaleBar), `App/` (point d'entrée, mode `--snapshot`).
- Polices libres (OFL) embarquées : Newsreader, Archivo, IBM Plex Mono.
- `scripts/bundle.sh` : assemble et signe (ad hoc) `build/GoSaver.app`.
- `docs/apercus/` : rendus clair/sombre.

**Objectif :** figer le langage visuel avant de coder les écrans, et disposer d'un moyen de vérifier le rendu sans capture d'écran (permission système).

## 2026-10-21 — Moteur de relevé

**Prompt :** « Oui, fais le premier commit et pousse sur GitHub, puis enchaîne sur le moteur de scan. »

**Réponse :** commit `cacd8f0` poussé ; moteur de relevé écrit, testé et branché sur l'écran.

**Modifications :**
- Paquet découpé : bibliothèque `GoSaverCore` (moteur sans interface), appli `GoSaver`, outil terminal `gosaver-survey`, tests `GoSaverCoreTests`.
- `Terrain`, `Zone` (découpage standard du Mac, dont les caches cachés sous `/private/var/folders`), `Enclave` (node_modules, DerivedData… → Carrières ; `Library/Caches` d'une appli → Marais).
- `Surveyor` : relevé parallèle (8 lieux à la fois), en lecture seule, flux d'évènements pour lever le brouillard en direct, taille réellement allouée sur le disque, accès refusés comptés.
- Interface : `AtlasModel`, Registre (motifs de terrain, enclaves regroupées, noms d'applis lisibles), bouton Sceau, échelle avec la part récupérable.
- Tests Swift Testing (6 tests, 11 cas) + `scripts/test.sh` pour les lancer sans Xcode.
- Correctif trouvé par les tests : propriétaire d'enclave décalé d'un dossier sous `/private/var`.

**Objectif :** disposer de chiffres réels et fiables avant de dessiner la carte. Relevé complet du disque en ~10 s : 164 Go relevés, 7,6 Go récupérables sans risque, UTM (31,6 Go) et Claude (13,3 Go) identifiés comme les plus gros lieux.

## 2026-10-22 — Carte 3D (plan-relief)

**Prompt :** « Oui, commite et pousse, puis attaque la carte 3D. » — puis, en cours de route : « Faudrait aussi que l'IA puisse savoir ce qui est déplaçable ou non. »

**Réponse :** commit `44f1c80` poussé ; carte 3D construite et vérifiée dans la vraie fenêtre ; la « déplaçabilité » est spécifiée dans la feuille de route (le moteur décide par règles, l'IA explique).

**Modifications :**
- `GoSaverCore/Cartography` : bruit déterministe, `Raster` (grille, distance, isolignes), `AtlasLayout` (côte organique, terrains proportionnels avec biais côtier, lieux, limite du disque, relief en couches).
- `GoSaver/Map` : `MapPrint` (impression gravée : mer et lignes d'eau, motifs, courbes de niveau, frontières, côte, noms avec halo), `AtlasScene` (relief drapé, planche, table, lampe, éclairage d'ambiance, brouillard hachuré), `AtlasMapView` (orbite bornée à la souris/trackpad, double-clic pour revenir), `SceneRenderer` (rendu 3D hors écran pour les instantanés).
- `AtlasModel` : lieux publiés par paquets (le relevé dans l'appli passe de plus d'une minute à 14 s), compteur de progression corrigé.
- `PlaceNames` : correctif « com.apple.geod » → « comle.geod », conteneurs anonymes.
- Halo papier sous l'en-tête, journaux `Log` (Console.app), 4 tests de géographie (10 tests au total).
- `docs/FEUILLE_DE_ROUTE.md` : étapes restantes et règles de déplaçabilité.

**Objectif :** donner à l'atlas son cœur visuel. Choix technique : pas de compilateur Metal sans Xcode, donc pas de shader ; on imprime une carte 2D riche et on la drape sur un relief (principe des plans-reliefs), ce qui garde la 3D et la légende parfaitement cohérentes.

## 2026-10-22 — Interaction avec la carte

**Prompt :** « Oui, commite et pousse la carte 3D, puis enchaîne sur l'interaction avec la carte. »

**Réponse :** commit `4fbba33` poussé ; survol, clic, jalon, vol de caméra et fiche de lieu ajoutés ; la sélection est partagée entre carte et Registre.

**Modifications :**
- `GoSaverCore/Cartography/Picking.swift` : `BoardGeometry` (planche ↔ grille, rayon → cellule touchée, avance par pas puis dichotomie) + 3 tests.
- `AtlasModel` : sélection et survol partagés, repères enrichis (terrain, fichiers, plus gros fichiers).
- `Ledger` : lignes cliquables, surlignage sélection/survol.
- `AtlasScene` : jalon d'arpenteur (fanion vermillon sans éclairage), planté avec une chute de 7 cm.
- `AtlasMapView` : gestes sur un calque transparent (la vue RealityKit gardait les clics), un seul geste de clic (simple/double par horodatage), visée par rayon, vol de caméra, étiquette de survol ; `Orbit.project` (projection inverse).
- `PlaceSheet` : fiche de lieu au coin corné, « Montrer dans le Finder », bouton Note.
- Contrôle de visée dans le mode instantané : croix calculée + jalon rendu par RealityKit → superposés au pixel près.
- Charte : composants §6.9 à §6.12.

**Objectif :** que la carte devienne un outil — on y lit un lieu, on le choisit, on voit ce qu'il contient — avant de brancher les actions (assécher, déplacer).

## 2026-10-22 — Assèchement (nettoyage)

**Prompt :** « J'ai testé : le clic et le survol marchent. Commite, pousse, puis enchaîne sur l'assèchement (nettoyage). »

**Réponse :** commit `38f394b` poussé ; assèchement des caches, journaux et (sur demande) de la corbeille, avec feuille de confirmation et érosion animée. Testé uniquement sur un faux dossier personnel : aucune suppression n'a été faite sur le vrai disque.

**Modifications :**
- `GoSaverCore/Drainage.swift` : `Drainer` (racines en liste blanche, plan en lecture seule, exécution qui revérifie chaque chemin résolu, liens supprimés en tant que liens, applis ouvertes épargnées), `RunningApp`.
- `Survey.removing` : relevé allégé après suppression, sans tout relever à nouveau.
- `AtlasModel` : déroulé planification → confirmation → assèchement → bilan ; corbeille décochée par défaut ; `landRevision` pour redessiner la carte.
- `DrainSheet` : feuille à double filet, case à cocher « registre », total en vermillon, mention « définitif » pour la corbeille, applis ouvertes listées.
- Bouton Sceau « Assécher les marais » après le relevé ; érosion : l'ancien relief s'affaisse, le nouveau se pose.
- `gosaver-survey --plan-assechement` : ce qui partirait, sans rien supprimer (6 Go de caches + 450 Mo de journaux sur ce Mac).
- 6 tests de sécurité et de mise à jour (19 au total), dont un lien piégé vers les Documents.

**Objectif :** première action qui libère vraiment de la place, avec des garde-fous vérifiés par des tests avant d'être confiés à l'utilisateur.

## 2026-10-22 — Accès complet au disque

**Prompt :** « J'ai testé l'assèchement, ça marche. Commite, pousse, puis enchaîne sur l'accès complet au disque. »

**Réponse :** commit `27d037f` poussé ; détection de la permission, feuille explicative en trois étapes, points d'entrée dans le Registre (Massif) et dans la feuille d'assèchement (corbeille illisible).

**Modifications :**
- `GoSaverCore/DiskAccess.swift` : statut par dossiers témoins (liste seulement, jamais de lecture de contenu), adresse directe du panneau des Réglages ; 2 tests (21 au total).
- `PaperModal` : feuille modale commune (voile + double filet), reprise par l'assèchement.
- `AccessSheet` : étapes I–III (ouvrir les Réglages, activer GoSaver ou le montrer dans le Finder, relancer), statut vérifié au retour dans l'appli, « Refaire le relevé » une fois l'accès accordé.
- `AtlasModel` : `diskAccess`, `accessSheetOpen`, revérification sur `didBecomeActive`.

**Objectif :** réduire le Massif « opaque » (43 Go dont 215 dossiers refusés) et rendre la corbeille lisible, sans jamais forcer : c'est l'utilisateur qui accorde la permission.

## 2026-10-22 — Accès introuvable avant le relevé

**Prompt :** capture d'écran + « je comprends pas où c'est pour appuyer. »

**Réponse :** défaut confirmé : le lien n'apparaissait qu'après un relevé. Corrigé.

**Modifications :** bloc « Zones fermées » + bouton « Ouvrir l'accès » en tête du Registre tant que l'accès manque ; commande « GoSaver › Accès complet au disque… » dans le menu ; mention sous le Massif réduite à l'information.

**Objectif :** qu'une action importante soit trouvable sans connaître l'appli.

## 2026-10-22 — « Ça ne me demande plus aucune autorisation »

**Prompt :** « Le registre n'est plus là mais ça ne me demande plus aucune autorisation. »

**Réponse :** diagnostic par journal (`Log.access`) : l'accès avait bien été accordé (le bloc disparaît alors, c'est voulu), puis la recompilation suivante l'a fait perdre, car la signature ad hoc change à chaque fois. macOS ne demande jamais cette permission par une fenêtre : elle se donne dans les Réglages.

**Modifications :** confirmation « Accès complet au disque accordé » en tête du Registre ; journal du statut d'accès à chaque vérification.

**Objectif :** que l'utilisateur voie toujours où il en est ; la vraie correction (signature stable) est proposée.

## 2026-10-22 — Signature stable

**Prompt :** « Oui, commite et pousse, puis crée le certificat de développement local pour que GoSaver garde l'accès complet au disque entre les compilations. »

**Réponse :** commit `5c3057b` poussé ; certificat « GoSaver Dev » créé et importé ; GoSaver signé avec, identité vérifiée stable entre deux compilations.

**Modifications :**
- Certificat autosigné RSA 2048, usage « signature de code », valable 10 ans, importé dans le trousseau de connexion avec accès réservé à `codesign`. Clé privée temporaire effacée, rien dans le dépôt.
- `scripts/bundle.sh` : signe avec « GoSaver Dev » s'il existe, sinon ad hoc (avec message).
- Vérification : compilations debug et release → empreintes (CDHash) différentes, exigence désignée identique (`identifier "fr.carlos.gosaver" and certificate root = H"cbc74d8f…"`).
- `docs/FEUILLE_DE_ROUTE.md` : section « Signature de développement » (vérifier, supprimer, limites).

**Objectif :** ne plus perdre l'accès complet au disque à chaque recompilation. Il faut le réactiver une dernière fois, car l'identité vient de changer.

## 2026-10-22 — Déplaçabilité

**Prompt :** « J'ai réactivé l'accès complet au disque. Commite, pousse, puis attaque la déplaçabilité dans le moteur. »

**Réponse :** commit `b5758fc` poussé ; juge de déplaçabilité écrit, testé, essayé en lecture seule sur les vrais dossiers, puis affiché dans la fiche de lieu. Accès complet au disque conservé après recompilation (signature stable vérifiée en conditions réelles).

**Modifications :**
- `GoSaverCore/Mobility/TargetVolume.swift` : disque cible (format lu par `statfs` : APFS, Mac OS étendu, exFAT, FAT32), place libre, ce que le format sait garder ; liste des disques externes branchés.
- `GoSaverCore/Mobility/MobilityJudge.swift` : constats par règles (emplacement → contenu → disque cible), verdict = constat le plus sévère, raison + conseil + précisions ; parcours du contenu (liens, programmes réels, dépôt git, iCloud, fichiers creux, plus gros fichier).
- Corrections après l'essai réel : seuls les vrais programmes comptent (pas une photo marquée exécutable), l'alternative (assécher, supprimer, passer par l'appli) prime, les dossiers de /Applications sont des applis, les programmes concernés sont cités.
- `PlaceSheet` : section « Outre-mer » (verdict coloré, raison, conseil, disque visé).
- `gosaver-survey --deplacabilite chemin…` : verdicts en lecture seule.
- 15 tests (36 au total).

**Objectif :** que rien ne parte sur le Lexar sans une raison vérifiable ; l'IA ne fera que reformuler ces verdicts.

## 2026-10-22 — Outre-mer (migration vers le Lexar) et icône

**Prompt :** « Commite, pousse, puis attaque l'Outre-mer : la migration vers le Lexar selon les verdicts. » — puis : « N'hésite pas aussi dans le lot à faire le logo pour pas que ce soit un truc sans icône. »

**Réponse :** commit `bd46250` poussé ; moteur de convoi écrit et testé (dont un vrai disque exFAT de test), feuille d'envoi, section Outre-mer du Registre, rapatriement ; icône dessinée et intégrée. Aucune donnée réelle n'a été déplacée pendant les essais.

**Modifications :**
- `GoSaverCore/Mobility/Convoy.swift` : envoi « copier sous nom provisoire → vérifier (tailles + SHA-256 du premier et du dernier Mo) → renommer → mettre l'original de côté → lien si besoin → supprimer » ; annulation propre à chaque étape ; registre de bord JSON sur le disque externe ; rapatriement par le même protocole.
- Bogues trouvés par les tests : calcul des chemins relatifs faussé par `/var` ↔ `/private/var` (désormais chemins relatifs fournis par l'énumérateur), date du registre non stable (arrondie à la seconde).
- 8 tests de convoi, dont un sur une image disque exFAT réelle de 64 Mo créée puis détruite (44 tests au total).
- `ConvoySheet`, bouton « Envoyer outre-mer » dans la fiche (verdicts Libre / Avec lien seulement), section Outre-mer du Registre avec « Rapatrier », suivi du branchement des disques.
- `IconArt` + `scripts/make-icon.sh` → `Assets/AppIcon.icns`, déclarée dans l'Info.plist.
- Accessibilité : chaque lieu du Registre redevient un bouton distinct pour VoiceOver.

**Objectif :** libérer de la place en envoyant des dossiers sur le Lexar, sans jamais risquer de perdre un fichier ; et donner à l'appli son identité visuelle.

## 2026-10-22 — Ranger les envois au bon endroit du Lexar

**Prompt :** « Oui j'ai testé et ça a mis sur un dossier GoSaver ; le truc c'est que justement on avait parlé que l'appli puisse repérer le dossier le plus adapté au lieu de tout regrouper sur un seul dossier, à moins que c'était déjà prévu. »

**Réponse :** c'était prévu (cadrage) mais pas encore fait — le dossier d'accueil unique était un intermédiaire non signalé. Ajout d'un moteur de rangement : propositions expliquées, choix, fusion, reclassement. Commit `5d7e919` poussé avant.

**Modifications :**
- `GoSaverCore/Mobility/Placement.swift` : familles de fichiers (extensions + mots de dossier), profil d'un dossier par échantillon, index du disque (3 023 dossiers en ~7 s), score = contenu semblable + nom qui annonce la famille + mots communs + profondeur + remplissage ; exclut projets de code, sous-dossiers techniques, sauvegardes d'appareil (déclassées), dossier d'accueil. Même nom près de la racine → fusion.
- Réglages issus de l'essai sur le vrai Lexar : IPT proposé dans `IPT` (fusion) et non dans un projet Android, Music dans `Music` et non dans un album « MUSIC », singulier/pluriel (« Projets » ↔ « Projet »).
- `Convoy` : envoi dans un dossier choisi, fusion (conflits renommés « (depuis le Mac) », rien d'écrasé, rapatriement de l'envoi seul), reclassement par renommage (le lien suit), identifiant de convoi stable.
- Interface : sélecteur de destination (propositions avec raison, dossier d'accueil, « Choisir un autre dossier… » limité au Lexar), bouton « Ranger » sur les envois existants.
- 7 tests (51 au total) ; `gosaver-survey --placement chemin…`.

**Objectif :** que chaque envoi rejoigne le rayonnage qui lui correspond sur le Lexar, en expliquant pourquoi, et que l'utilisateur garde le dernier mot.

## 2026-10-22 — « Après Ranger, ça reste toujours là »

**Prompt :** « Après ranger il reste toujours sur l'interface et on peut plus appuyer sur ranger » — puis « my bad, on peut toujours cliquer dessus » et « mais ça reste toujours là ». Puis : « faire un dossier corbeille sur le Lexar pour les trucs qu'on ne veut pas, qui s'élimine tout seul. »

**Réponse :** le rangement avait bien eu lieu (JPEG dans `Lexar/Perso/JPEG`, registre à jour). Reproduit sur un disque exFAT de test : la feuille fonctionne ; le vrai défaut est que la ligne de l'envoi dans le Registre ne disait pas où il se trouvait, donc rien ne semblait changer. Corrigé. La « corbeille du Lexar » correspond au Lazaret prévu au cadrage : proposée comme prochaine étape.

**Modifications :**
- Registre › Outre-mer : chaque envoi affiche « à ranger » (encore dans le dossier d'accueil) ou « dans Perso » ; bouton « Ranger » ou « Déplacer » selon le cas.
- Registre de bord lu dès l'ouverture (il ne l'était qu'au retour au premier plan).
- `GOSAVER_HARBOR` (développement) : faire pointer l'appli vers un disque de test ; journal `Log.convoy`.

**Objectif :** que l'état de chaque envoi soit visible d'un coup d'œil, et pouvoir déboguer les convois sans toucher au vrai disque.

## 2026-10-22 — Lazaret (corbeille du Lexar)

**Prompt :** « Commite, pousse, puis fais le Lazaret : la corbeille sur le Lexar qui se vide toute seule au bout de 30 jours. »

**Réponse :** commit `3979006` poussé ; Lazaret construit, testé sur faux disque et sur un disque exFAT de test (expiration automatique, restauration). Aucune donnée réelle déplacée.

**Modifications :**
- `GoSaverCore/Mobility/Lazaret.swift` : mise au Lazaret (même protocole que les convois, rangement par jour « GoSaver Lazaret/2026-10-22/… »), registre `registre-du-lazaret.json` sur le disque, restauration, expiration (suppression définitive après 30 jours, uniquement à l'intérieur du Lazaret), suppression immédiate sur demande.
- Règles : refus pour système, bac à sable et **iCloud** (isoler un fichier synchronisé l'effacerait de tous les appareils) ; le « déconseillé » est accepté (on ne compte plus s'en servir) ; liens symboliques et place revérifiés.
- Droits remis à la normale (644/755) au retour d'un disque exFAT, pour les rapatriements et les restaurations.
- Interface : « Mettre au Lazaret » dans la fiche, feuilles de confirmation, section Lazaret du Registre (jours restants, Restaurer, Supprimer), purge à l'ouverture avec message.
- 9 tests (60 au total).

**Objectif :** une corbeille sans risque sur le Lexar : le Mac est libéré tout de suite, on a 30 jours pour changer d'avis, puis le ménage se fait seul.

## 2026-10-22 — Ruines (fichiers mystères) et Réglages complets

**Prompt :** « Commite, pousse, puis attaque l'enquête sur les fichiers mystères (Ruines). » — en cours de route : « Peux-tu aussi activer une option dans les paramètres pour activer et désactiver le langage de jeu vidéo » puis « et bien sûr faire des paramètres bien complets, avec tout ce qui a besoin d'être là-bas ».

**Réponse :** commit `315b5d0` poussé ; expertise des ruines calibrée sur le vrai disque (lecture seule), fiche d'expertise, isolement au Lazaret ; fenêtre de Réglages complète, chaque option branchée ; lexique Atlas/Classique appliqué en direct.

**Modifications :**
- `GoSaverCore/Ruins/Clues.swift` : indices (vrai contenu par « nombre magique » — un `.ts` vidéo ou TypeScript —, type macOS, provenance et appli de téléchargement lues dans les attributs étendus, dates, dernière ouverture Spotlight).
- `GoSaverCore/Ruins/Expertise.swift` : données d'applis disparues (appli absente ET intacte depuis 90 j, prudent : BraveSoftware ↔ Brave Browser), doublons à contenu identique (empreinte complète), installeurs d'applis installées, téléchargements interrompus, fichiers d'origine inconnue (« à examiner », jamais isolés seuls).
- Sur ce Mac : 12 ruines sûres (~1,7 Go : Whisky 896 Mo, Opera, OpenEmu, Wondershare, Docker, GIMP, GitHub Desktop, PokeMMO-v62.dmg, steam.dmg…) ; `data_Loogatox` × 2 correctement non signalés (contenus différents).
- Interface : terrain Ruines sur la carte, section Ruines du Registre, `RuinSheet` (tampon, résumé, indices, Lazaret/Conserver/Finder), « Isoler les N ruines sûres ».
- `Surveyor` : dossiers exclus. `Place.with(terrain:)`.
- `Preferences`, `Words`, `SettingsView` (Général, Relevé, Nettoyage, Disque externe, Accès, À propos).
- 8 tests (68 au total).

**Objectif :** reconnaître ce qui ne sert plus en expliquant pourquoi, et laisser l'utilisateur régler l'appli à son goût, y compris son ton.

## 2026-10-22 — « Où est le bouton pour accéder aux paramètres ? »

**Prompt :** capture d'écran + « où est le bouton pour accéder au paramètre ».

**Réponse :** les Réglages n'étaient accessibles que par le menu GoSaver et ⌘, — convention Mac, mais invisible dans la fenêtre. Ajout d'un bouton.

**Modifications :** bouton « Réglages » (icône engrenage + texte, style Note) en haut à droite de la carte, via `SettingsLink`.

**Objectif :** qu'aucune fonction importante ne dépende de la connaissance des conventions macOS.

## 2026-10-22 — Désinstalleur, corbeille, Registre complet, build/ et convoi animé

**Prompts :** « C'est bon ça marche … tu peux continuer » ; « là par exemple je veux supprimer DaVinci Resolve, j'ai pas de bouton » ; « et quand c'est écrit par exemple 1159 autres lieux, j'aimerais bien voir pour pouvoir supprimer si des trucs m'intéressent plus ».

**Réponse :** commit `2f8ca74` poussé ; dossiers `build/` reconnus (≈ 4 Go chez l'utilisateur) ; convoi animé sur la carte ; désinstalleur et corbeille dans la fiche ; Registre dépliable. Vérifié dans l'appli (fiche et feuille de désinstallation de DaVinci, sans désinstaller).

**Modifications :**
- `Enclave` : `build/` à côté d'un `pubspec.yaml`, `build.gradle`, `CMakeLists.txt`, `Package.swift`… → Carrières ; `.dart_tool`. Un `build` ordinaire n'est jamais touché.
- `AtlasScene` : route du convoi (tirets vermillon, arc au-dessus du relief) et petit navire orienté, avancés au rythme de la copie ; `AtlasModel.convoyProgress`.
- `GoSaverCore/Uninstaller.swift` : applis du dossier, restes exacts (données, caches, conteneur, préférences, état des fenêtres, journaux, données web, scripts, lancement automatique), désinstalleur de l'éditeur, besoin de mot de passe ; refus si ouverte ou appli d'Apple. 3 tests (72 au total).
- Fiche : « Désinstaller » (applis) ou « Mettre à la corbeille » (fichiers de l'utilisateur, hors zones gérées par macOS) ; mise à la corbeille via `NSWorkspace.recycle` (comme le Finder, récupérable).
- Registre : « et N autres · afficher » déplie par 50, « Replier ».
- `gosaver-survey --desinstaller chemin` (lecture seule).

**Objectif :** pouvoir agir sur n'importe quel lieu du disque — y compris désinstaller proprement une appli — en restant récupérable.

## 2026-10-22 — Sélection multiple et actions en lot

**Prompt :** « C'est bon mais là sur la droite plein d'applis et c'est chiant d'aller un à un pour désinstaller ou mettre à la corbeille ; fais en sorte qu'on puisse sélectionner pour supprimer ou pour déplacer ou autre. »

**Réponse :** mode sélection dans le Registre, barre d'actions, feuille récapitulative avec éléments écartés et leur raison ; vérifié dans l'appli jusqu'à la feuille (8 dossiers build, 4,43 Go), sans exécuter.

**Modifications :**
- `App/Batch.swift` : `BatchAction` (Supprimer, Outre-mer, Lazaret), vérification de chaque emplacement avec les mêmes règles que les actions unitaires (applis → désinstallation avec restes ; désinstalleur de l'éditeur ou mot de passe requis → écarté ; zones macOS → écarté avec explication ; outre-mer → juge + meilleure proposition de rangement ; Lazaret → juge), exécution (une seule mise à la corbeille macOS, convois/Lazaret un par un), bilan.
- Registre : « Sélectionner/Terminer », cases sur les lieux et les ruines, « tout ce qui est affiché » par section, barre « N sélectionnés · X Go » ; un groupe (« build × 8 ») coche tous ses dossiers.
- Désinstalleur : conteneur partagé « ÉQUIPE.identifiant » inclus (suffixe exact) ; 1 test (73 au total).

**Objectif :** traiter des dizaines de lieux en une fois sans perdre la vérification élément par élément.

## 2026-10-22 — « Beaucoup de doublons dans les applis, j'ai deux fois Claude »

**Prompt :** « Ça marche ; sinon je remarque qu'il y a beaucoup de doublons dans les applis, genre j'ai deux fois Claude. »

**Réponse :** pas des doublons de fichiers : le paquet (`/Applications/Claude.app`, 646 Mo) et les données (`~/Library/Application Support/Claude`, 13,3 Go) apparaissaient comme deux lieux au même nom. Regroupés en une ligne par appli.

**Modifications :**
- `Archaeologist.ownerApp(for:)` : rattache un emplacement à son appli (paquet par nom, conteneurs et conteneurs partagés par identifiant exact ou extension « identifiant.xxx », données par nom) ; jamais par ressemblance lointaine. 2 tests (75 au total).
- Registre et carte : dans Applications, une ligne par appli = paquet + données + conteneurs (« Claude — 14 Go »).
- Fiche : liste « Emplacements » (Appli, Données, Conteneur, Données partagées) ; « Désinstaller » disponible depuis le regroupement.
- Lots : une appli désinstallée emporte ses données, qui ne sont plus listées une seconde fois.

**Objectif :** une appli = une ligne, avec son vrai poids total.

## 2026-10-23 — Signature bloquée par une fenêtre cachée

**Prompt :** « C'est parce que j'avais mis en arrière-plan et j'ai rien accepté. »

**Réponse :** relance de l'assemblage ; l'utilisateur a accepté la demande d'accès au trousseau ; signature « GoSaver Dev » vérifiée (`fr.carlos.gosaver`). Registre regroupé vérifié à l'écran (« Claude — 14 Go »). L'accès complet au disque est à réactiver une fois : la version de secours signée provisoirement, lancée pendant l'échec, a fait invalider l'autorisation par macOS.

**Modifications :** `bundle.sh` échoue désormais clairement si la signature avec « GoSaver Dev » rate (message + commande `security unlock-keychain`), au lieu de produire une appli mal signée.

**Objectif :** ne plus jamais livrer une appli dont la signature ferait perdre l'accès complet au disque.

## 2026-10-23 — Supprimer aussi les applis protégées

**Prompt :** capture de la feuille « Supprimer » (Lightroom, BloonsTD6+, Acrobat, NordVPN… écartés « mot de passe administrateur requis ») + « Tu ne peux pas vraiment trouver une chose pour forcer à supprimer ? Sinon mets un bouton qui mène à l'emplacement Finder. »

**Réponse :** les deux. GoSaver repasse par le Finder pour ce qu'il n'a pas le droit de déplacer : le Finder affiche sa propre demande de mot de passe, comme lors d'un glisser vers la corbeille. Bouton « Finder » sur chaque élément encore écarté.

**Modifications :**
- `App/FinderTrash.swift` : « tell application "Finder" to delete » via `osascript`, chemins passés en arguments (sans risque d'injection) ; annulation et refus d'automatisation reconnus avec un message clair.
- `AtlasModel.recycle` : corbeille en deux temps (NSWorkspace, puis Finder pour le reste), succès vérifié sur le disque ; utilisé par la fiche et par les lots.
- Lots : les applis « mot de passe » ne sont plus écartées (« · mot de passe ») ; restent écartées celles qui ont un désinstalleur d'éditeur ; bouton « Finder » sur chaque élément écarté.
- `bundle.sh` : `NSAppleEventsUsageDescription` (texte de la demande d'automatisation).

**Objectif :** pouvoir supprimer toute appli de l'utilisateur, sans que GoSaver ne manipule jamais le mot de passe administrateur.

## 2026-10-23 — Critique de design, audit d'accessibilité, clics perdus sur la carte

**Prompt :** « j ai trouver un autre defaut parfois quand je clique sur … un bouton dans la partie de gauche avec la carte … pour recliquer faut cliquer autre part » (pendant les passes de finition).

**Réponse / modifications :**
- Critique : sous-titre des homonymes et des noms génériques dans le registre (« Developer · Bibliothèque système »), titres de section collants au défilement, chiffre récupérable en bleu mer, « 0 » de l'échelle aligné, caméra recadrée.
- Clics perdus : la vue AppKit de RealityKit ne reçoit plus la souris (`allowsHitTesting(false)`), seul le calque de gestes SwiftUI la reçoit.
- Accessibilité : contrastes vérifiés (tous ≥ 4,5:1 pour le texte), les tirets « — » passent en sépia lisible avec une étiquette VoiceOver, les animations des fiches respectent « Réduire les animations », l'aide VoiceOver des lignes suit le mode sélection.

**Objectif :** finitions avant la sécurité et l'IA locale.

## 2026-10-23 — Rédaction et sécurité

**Prompt :** « c'est bon continue »

**Réponse / modifications :**
- Rédaction : le mode Classique n'emploie plus « brouillard », « géomètre », « Lazaret » ni « rendus à la mer » ; « Finder » devient « Montrer », « Décocher » devient « Tout décocher », le bouton d'attente suit le lexique.
- Sécurité 1 : `InUse` (GoSaverCore) interroge `lsof` avant de ranger, mettre au Lazaret, jeter ou désinstaller, en lot comme à l'unité. Si un programme tient un fichier ouvert (VM UTM allumée, appli ouverte), c'est refusé avec son nom. 4 tests (79 au total).
- Sécurité 2 : la liste des dossiers partis « avec lien » est gardée sur le Mac ; si le disque externe est débranché, le registre prévient lesquels sont inaccessibles.

**Objectif :** ne jamais abîmer une copie en cours d'utilisation, et ne pas laisser l'utilisateur sans explication quand un lien est rompu.

## 2026-10-23 — IA locale (Apple Intelligence)

**Prompt :** suite du plan (« je viens d'activer apple intelligence »).

**Réponse / modifications :**
- `Advisor` : avis du modèle Foundation Models exécuté sur le Mac, hors ligne. Génération guidée par schéma dynamique (les macros `@Generable` ne sont pas fournies sans Xcode) : à quoi sert l'élément, raisonnement, puis conseil choisi **uniquement parmi les actions permises par le moteur**.
- Faits fournis : nature connue du terrain, taille, emplacements, plus gros fichiers, dernière ouverture Spotlight, verdict et conseil du moteur. Mode déterministe (greedy), « garder » en dernière option, raisonnement avant le choix : sans ces réglages le modèle conseillait toujours « garder ».
- Section « Avis du cartographe » / « Avis de l'IA » dans les fiches de lieu et de ruine, avec mention « peut se tromper, la décision reste la tienne ».
- Fiches défilantes quand la fenêtre est petite ; tailles du registre jamais coupées sur deux lignes ; puces « — » cachées à VoiceOver ; le Lazaret d'une ruine passe aussi par le garde-fou « en cours d'utilisation ».

**Objectif :** une IA qui explique et conseille sans jamais décider à la place de l'utilisateur.
