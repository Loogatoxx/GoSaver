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
