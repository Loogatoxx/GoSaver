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
