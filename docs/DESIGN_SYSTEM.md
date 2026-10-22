# GoSaver — Charte graphique « Atlas »

> Version 0.1 · 2026-10-21
> Référence unique pour l'interface, les animations et les sons. Si une valeur n'est pas ici, elle n'existe pas : on l'ajoute ici d'abord, puis dans `Sources/GoSaver/Design/`.

---

## 1. Idée directrice

**Ton disque est un territoire.** GoSaver est un atlas que l'on dresse : on survole, on relève, on assèche, on fait migrer. Tout ce qui est dessiné représente une donnée réelle. Rien n'est décoratif « pour faire joli ».

Le langage visuel vient de la **cartographie imprimée** (cartes d'état-major, cartes IGN, atlas du XIXᵉ siècle) : papier, encre, hachures, courbes de niveau, cartouches, échelles graduées. Pas de « dashboard », pas de cartes-widgets.

### La métaphore, terme à terme

| Réalité | Sur la carte | Pourquoi |
|---|---|---|
| Disque interne (256 Go) | **L'île** dans son cadre | Un territoire fini, entouré d'eau |
| Espace libre | **La mer** | Plus on nettoie, plus la mer gagne : c'est lisible sans légende |
| Taille d'un dossier | **Altitude** du relief | Les gros dossiers sont des montagnes, on les voit de loin |
| Non scanné | **Brouillard** (hachures croisées sur papier) | Se dissipe pendant le relevé |
| macOS / système | **Massif** (hachures de roche, intouchable) | Terre de la Couronne : on ne creuse pas |
| Applications | **Cités** (îlots bâtis) | Habitées, on ne les rase pas |
| Caches | **Marais** (sédiments pointillés) | Se reforment seuls, on peut les assécher |
| Téléchargements | **Delta / port** | Là où tout arrive et s'accumule |
| Documents | **Champs** (sillons parallèles) | Cultivés, ordonnés, à toi |
| Photos, vidéos, musique | **Forêts** (pointillé d'arbres) | Denses, lourdes, précieuses |
| Dev (`node_modules`, DerivedData, Gradle…) | **Carrières** (motif de déblais) | Creusées par les outils, régénérables |
| Fichiers mystères | **Ruines** (traits interrompus) | Origine inconnue → à expertiser |
| SSD Lexar | **Outre-mer**, second continent | Destination des convois |
| Quarantaine | **Le Lazaret** (île du port) | Historiquement, l'île où l'on isolait les cargaisons douteuses : exactement son rôle |

---

## 2. Liste noire (non négociable)

- Emojis (dans l'UI, les textes, les notifications).
- Dégradés multicolores. Seul dégradé autorisé : l'ombrage du relief, **monochrome**, dérivé de la lumière de la scène 3D.
- Barres d'accent arrondies (trait vertical à gauche d'un texte, pilule horizontale, *capsule* de statut).
- Texte gris. Le texte secondaire est **sépia** (encre délavée), jamais un gris neutre.
- Cartes-widgets génériques (rectangle arrondi + icône + chiffre + sous-titre).
- Formes géométriques abstraites décoratives (blobs, cercles flous, orbes).
- Glassmorphism (verre dépoli) en dehors de ce qu'impose macOS pour la barre de titre.
- Icônes SF Symbols utilisées comme illustration. Les SF Symbols restent permis **dans les menus et la barre d'outils**, à leur taille standard.

---

## 3. Couleurs

Deux thèmes : **Papier** (clair) et **Lampe** (sombre : la même carte, lue sous une lampe de bureau). Les couleurs sont des **encres**, pas des aplats vifs : peu saturées, toujours chaudes.

### 3.1 Jetons

| Jeton | Rôle | Papier | Lampe |
|---|---|---|---|
| `paper` | Fond principal | `#F1E9D8` | `#17140F` |
| `paperRaised` | Feuille posée sur la carte (panneaux) | `#F8F2E6` | `#211C15` |
| `paperSunken` | Zones en creux, champs de saisie | `#E6DCC6` | `#100E0A` |
| `ink` | Texte principal, traits forts | `#1E1912` | `#EFE5D0` |
| `inkFaded` | Texte secondaire (sépia, **pas gris**) | `#5A4630` | `#CDB792` |
| `contour` | Courbes de niveau, filets (jamais du texte) | `#9C7A52` | `#7A6347` |
| `sea` | Eau, espace libre, hydrographie | `#2E5A6E` | `#79A9BD` |
| `seaWash` | Lavis de la mer (fond d'eau) | `#C9D6D3` | `#1B2A2F` |
| `vermilion` | Accent unique : action principale, tracé de route, alerte | `#A63412` | `#E46A3E` |
| `forest` | Validé, sûr, terminé | `#3F5E2F` | `#9DB77A` |
| `ochre` | Avertissement, attention requise | `#7E500B` | `#D9A54A` |
| `fog` | Brouillard (hachures) | `#1E1912` @ 18 % | `#EFE5D0` @ 14 % |

**Règle d'or** : un seul accent (`vermilion`) par écran pour l'action principale. `sea`, `forest`, `ochre` sont **sémantiques**, jamais décoratifs.

### 3.2 Contrastes (cible WCAG AA)

| Paire | Papier | Lampe | Seuil |
|---|---|---|---|
| `ink` / `paper` | 14,5 : 1 | 14,7 : 1 | 4,5 |
| `inkFaded` / `paper` | 7,4 : 1 | 9,4 : 1 | 4,5 |
| `vermilion` / `paper` (texte) | 5,6 : 1 (4,9 sur `paperSunken`) | 5,6 : 1 | 4,5 |
| `paper` sur `vermilion` (bouton) | 5,6 : 1 | 5,6 : 1 | 4,5 |
| `sea` / `paper` | 6,2 : 1 | 7,2 : 1 | 4,5 |
| `ochre` / `paper` | 5,7 : 1 (5,1 sur `paperSunken`) | 8,3 : 1 | 4,5 |
| `contour` / `paper` | 3,3 : 1 | 3,2 : 1 | 3 (graphique uniquement) |

> Valeurs calculées (formule WCAG 2.1) le 2026-10-21. `contour` n'est **jamais** utilisé pour du texte.

### 3.3 Catégories de terrain

Les catégories ne se distinguent **pas par la couleur** (daltonisme + liste noire « trop coloré ») mais par le **motif** cartographique, comme sur une vraie carte imprimée en une ou deux encres :

| Terrain | Motif | Encre |
|---|---|---|
| Massif (système) | Hachures de pente serrées | `ink` |
| Cités (apps) | Îlots pleins, rues en réserve | `ink` |
| Marais (caches) | Tirets horizontaux courts | `sea` |
| Delta (téléchargements) | Bras d'eau ramifiés | `sea` |
| Champs (documents) | Sillons parallèles orientés | `contour` |
| Forêts (médias) | Pointillé en semis d'arbres | `forest` |
| Carrières (dev) | Déblais (petits triangles irréguliers) | `contour` |
| Ruines (mystères) | Traits interrompus + croix | `vermilion` |

---

## 4. Typographie

Trois voix, comme sur une carte : le **titre** gravé, les **toponymes** (noms de lieux), les **cotes** (chiffres relevés).

| Voix | Police | Usage |
|---|---|---|
| Gravure | **Newsreader** (OFL) — tailles optiques | Titres, cartouches, nombres héroïques |
| Hydrographie | **Newsreader Italic** | Tout ce qui touche à l'eau / l'espace libre, citations de l'IA. Convention cartographique : l'eau s'écrit en italique |
| Toponymes | **Archivo** (OFL), axe de chasse 62–125 | Noms de régions en CAPITALES espacées, interface, boutons |
| Cotes | **IBM Plex Mono** (OFL) | Tailles, chemins, dates, compteurs (chiffres à chasse fixe → pas de « danse » pendant l'animation) |

Repli si une police manque : New York (serif système), SF Pro, SF Mono.

### 4.1 Échelle

| Jeton | Police | Taille / interligne | Graisse | Chasse / approche |
|---|---|---|---|---|
| `display` | Newsreader 72 opsz | 56 / 60 | 300 | — / −1 % |
| `title` | Newsreader 36 opsz | 28 / 34 | 400 | — |
| `heading` | Newsreader 16 opsz | 19 / 24 | 500 | — |
| `region` | Archivo | 11 / 14 | 600 | 112 % / **+18 %**, CAPITALES |
| `body` | Archivo | 13 / 19 | 400 | 100 % |
| `bodyStrong` | Archivo | 13 / 19 | 600 | 100 % |
| `label` | Archivo | 11 / 15 | 500 | 100 % / +2 % |
| `water` | Newsreader Italic | 15 / 21 | 400 | — |
| `figure` | IBM Plex Mono | 13 / 18 | 500 | chiffres tabulaires |
| `figureLarge` | IBM Plex Mono | 22 / 26 | 400 | chiffres tabulaires |

Tailles minimales : 11 pt (jamais en dessous), Dynamic Type respecté via `@ScaledMetric`.

---

## 5. Espacement, traits, formes

### 5.1 Espacement (base 4)

`s1 = 4` · `s2 = 8` · `s3 = 12` · `s4 = 16` · `s5 = 24` · `s6 = 32` · `s7 = 48` · `s8 = 64`

### 5.2 Traits (remplacent les ombres et les arrondis)

| Jeton | Épaisseur | Usage |
|---|---|---|
| `hairline` | 0,5 pt | Filets internes, courbes de niveau secondaires |
| `rule` | 1 pt | Bordures de panneaux, séparateurs |
| `ruleStrong` | 2 pt | Cadre de carte (*neatline*) |
| **Double filet** | 2 pt + 3 pt d'écart + 0,5 pt | Cartouche (bloc-titre), fenêtres modales |

Les **séparateurs** sont des filets **gradués** (petites graduations tous les 8 pt aux extrémités, comme une règle), jamais une barre pleine arrondie.

### 5.3 Rayons

`radius0 = 0` (défaut : cadres, cartouches, panneaux) · `radius1 = 2` (boutons, champs) · c'est tout. Aucun élément en pilule.

### 5.4 Élévation

Pas d'ombre floue générique. Un panneau est une **feuille posée** : ombre portée courte, dure, décalée vers le bas-droite (lumière de la lampe en haut-gauche).

| Jeton | Décalage | Flou | Opacité (`ink`) |
|---|---|---|---|
| `sheet` | (1, 2) | 0 | 12 % |
| `sheetLifted` | (2, 5) | 2 | 16 % |

Texture : grain de papier (bruit fin, 3 % d'opacité, statique, généré une fois) sur `paper` et `paperRaised`.

---

## 6. Composants

### 6.1 Cartouche (`Cartouche`)
Bloc-titre encadré d'un double filet, comme le cartouche d'une carte ancienne. Contient : titre (`title`), sous-titre de relevé (`water`), date et échelle (`figure`).
- Une seule par écran, en bas à gauche de la carte.
- Jamais d'icône.

### 6.2 Bouton
| Variante | Visuel | Usage |
|---|---|---|
| **Sceau** (principal) | Fond `vermilion`, texte `paper` en `region`, `radius1`, ombre `sheet` | Une seule action principale par écran (« Lancer le relevé », « Assécher ») |
| **Tracé** (secondaire) | Fond transparent, bordure `rule` `ink`, texte `ink` | Actions secondaires |
| **Note** (tertiaire) | Texte `ink` souligné d'un filet `hairline` décalé de 3 pt | Liens, « Voir le détail » |

États : survol → l'ombre passe à `sheetLifted` et le bouton monte de 1 pt ; appui → ombre nulle, descend de 1 pt (effet tampon encreur) + son *Tampon* ; désactivé → encre à 45 %, motif de hachure fine ; chargement → le libellé est remplacé par une ligne de pointillés qui progresse (pas de *spinner* circulaire).
Clavier : `Entrée` déclenche le Sceau, `Échap` annule, anneau de focus = double filet `vermilion` 1 pt décalé de 2 pt.

### 6.3 Échelle graduée (`ScaleBar`)
Remplace la barre de progression et la jauge d'occupation. Barre d'échelle cartographique en cases alternées noir/papier, graduée en Go.
- Montre : occupé / libre (= mer) / récupérable (hachures `vermilion`).
- Les chiffres sont posés **au-dessus** des graduations, en `figure`.

### 6.4 Toponyme (`RegionLabel`)
Nom de région posé sur la carte en `region`, suit la courbure du relief quand c'est possible. Taille proportionnelle à l'importance (3 niveaux). Survol → souligné d'un filet `hairline` et son *Papier*.

### 6.5 Fiche d'expertise (`SurveyCard`)
Pour un fichier mystère (ruine). Feuille `paperRaised`, coin supérieur droit corné (pli dessiné).
- En-tête : nom du fichier (`figure`), taille.
- Corps : le résumé de l'IA en `water` (italique) entre guillemets typographiques « ».
- Indices relevés (provenance, appli créatrice, dernière ouverture) en liste à tirets cadratins.
- Verdict : tampon incliné de −4° (« À ISOLER », « À CONSERVER »), encre `vermilion` ou `forest`, texture d'encre irrégulière.

### 6.6 Registre (`Ledger`)
Panneau latéral droit, liste des régions/éléments. Lignes séparées par des filets `hairline`, colonnes alignées (nom à gauche, cote en `figure` à droite, alignées sur la virgule). Sélection : fond `paperSunken` + nom en `bodyStrong`. **Pas** de barre d'accent.

### 6.7 Légende (`Legend`)
Coin inférieur droit. Les motifs de terrain avec leur nom. Cliquer un motif isole cette catégorie sur la carte (les autres passent en encre à 25 %).

### 6.8 Convoi (`Convoy`)
Migration vers Outre-mer : tracé pointillé `vermilion` de l'île au continent, petit navire gravé qui suit la route au rythme réel de la copie. La route reste dessinée après coup (historique visible).

### 6.9 Jalon (`marker`)
Piquet d'arpenteur planté sur le lieu sélectionné : tige d'encre, fanion vermillon sans éclairage (il reste lisible quel que soit l'angle de la lampe). Il tombe de 7 cm et se fiche dans le relief en 320 ms.

### 6.10 Étiquette de survol
Petite feuille `paperRaised`, filet `hairline`, ombre `sheet` : nom en `bodyStrong`, terrain en `label`, taille en `figure`. Suit le pointeur avec un décalage de 16 × 18 pt, ne capte jamais les clics.

### 6.11 Fiche de lieu (`PlaceSheet`)
Variante de la fiche d'expertise (§6.5) pour un lieu sélectionné. Elle remplace l'en-tête en haut à gauche de la carte, coin corné, et contient : terrain, nom, taille et nombre de fichiers, « se reforme seul » si le terrain se régénère, les six plus gros fichiers, le chemin (sélectionnable), « Montrer dans le Finder » (Tracé) et « Fermer » (Note, touche Échap).

### 6.12 Gestes sur la carte
| Geste | Effet |
|---|---|
| Glisser | Tourner autour du point visé (inclinaison bornée de 25° à 80°) |
| Pincer | S'approcher ou s'éloigner (0,5 à 3,4 m) |
| Survoler | Étiquette du lieu, ligne du Registre surlignée |
| Clic | Sélection : jalon planté, vol de caméra (0,9 s), fiche ouverte |
| Double-clic | Retour à la vue d'ensemble |

### 6.13 Tampon (`Stamp`)
Verdict d'expertise : capitales espacées dans un double cadre, encre à 88 %, incliné de −4°. « À ISOLER » en `vermilion`, « À EXAMINER » en `ochre`.

### 6.14 Réglages
Fenêtre native à onglets (icônes SF Symbols autorisées : c'est une barre d'outils), contenu aux couleurs de la charte : rubriques en `region`, règles graduées entre rubriques, chaque réglage = intitulé `bodyStrong` + une phrase d'explication `label` + sa commande. Cases à cocher « registre » (`SurveyCheckboxStyle`), jamais d'interrupteur en pilule.

### 6.15 Lexique
Deux voix, choisies dans les Réglages : **Atlas** (Marais, Carrières, Lazaret, Outre-mer…) et **Classique** (Caches, Outils de dev, Corbeille du disque externe, Disque externe…). Tout texte d'interface qui porte la métaphore passe par `Words` ; les chiffres et les verdicts ne changent jamais.

---

## 7. Mouvement

| Jeton | Durée | Courbe | Usage |
|---|---|---|---|
| `quick` | 120 ms | `easeOut` | Survol, focus |
| `settle` | 280 ms | ressort (réponse 0,32 · amortissement 0,86) | Panneaux, sélection |
| `survey` | 900 ms | `easeInOut` | Survol caméra d'une région à l'autre |
| `erosion` | 1 600 ms | `easeIn` puis rebond léger | Le relief s'abaisse après un nettoyage |
| `fogLift` | progressif | suit le scan réel | Le brouillard se lève région par région |

Principes :
1. **Chaque mouvement raconte un fait** (la terre baisse = place libérée). Jamais d'animation d'attente gratuite.
2. **Les chiffres roulent** (compteur mécanique) en chiffres tabulaires.
3. **Réduire les animations** (réglage macOS) : caméra en coupe franche, brouillard en fondu, relief sans rebond. Aucune info n'est portée seulement par le mouvement.

---

## 8. Sons

Synthèse **modale** (résonances d'objets réels) + bruit filtré + réverbération par convolution d'une petite pièce boisée. Jamais d'onde carrée ou triangulaire nue. Volume global par défaut −18 dB sous le niveau système ; respecte « Lire les effets sonores de l'interface ».

| Événement | Son | Matière |
|---|---|---|
| Clic / sélection | *Bois* | Bloc de buis, 3 modes inharmoniques, 60 ms |
| Survol d'une région | *Papier* | Froissement très court, bruit passe-bande |
| Appui sur le Sceau | *Tampon* | Coup feutré grave + claquement de bois |
| Pendant le relevé | *Vent* | Souffle passe-bande lent, modulé par la vitesse du scan |
| Région découverte | *Lame* | Note de lamellophone (kalimba), gamme pentatonique ; plus grave quand la région est grosse |
| Assèchement | *Sable* | Granulaire qui s'écoule + « thoum » feutré final |
| Départ d'un convoi | *Cloche* | Petite cloche de navire, très amortie |
| Mise au Lazaret | *Loquet* | Loquet métallique + bois |
| Erreur | *Deux coups* | Deux coups de bois descendants, secs |
| Relevé terminé | *Bols* | Accord de trois bols chantants, réverbération longue |

---

## 9. Mise en page de la fenêtre principale

```
┌───────────────────────────────────────────────────────────────┐
│  barre de titre macOS (transparente)          [Relever] [⚙]  │
├───────────────────────────────────────────────┬───────────────┤
│                                               │  REGISTRE     │
│            CARTE 3D (pleine page)             │  ───────────  │
│   île · mer · brouillard · Outre-mer          │  lignes…      │
│                                               │               │
│ ╔═══════════════╗               ┌──────────┐  │               │
│ ║ Cartouche     ║               │ Légende  │  │               │
│ ╚═══════════════╝               └──────────┘  │               │
├───────────────────────────────────────────────┴───────────────┤
│  Échelle graduée : 0 ─────────────────────────────── 228 Go   │
└───────────────────────────────────────────────────────────────┘
```

Fenêtre minimale 1 000 × 680 pt. Le Registre se replie sous 1 180 pt de large.

Navigation (barre latérale à gauche, très étroite, toponymes verticaux) : **Atlas** · **Outre-mer** (SSD) · **Lazaret** (quarantaine) · **Réglages**.

---

## 10. Ton éditorial (voir `/ux-copy`)

Vocabulaire d'expédition, **mais l'information prime** : la donnée vient d'abord, la métaphore ensuite.
- Bien : « Marais des caches — 4,2 Go récupérables. Ils se reformeront seuls. »
- Mal : « Les brumes mystérieuses du marais cachent des trésors… »

Les nombres sont toujours exacts et vérifiables (même unité que le Finder : Go en base 10).
