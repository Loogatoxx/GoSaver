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
