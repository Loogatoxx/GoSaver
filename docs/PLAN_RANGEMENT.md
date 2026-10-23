# Plan de rangement — Mac et Lexar (2026-10-23)

Rien n'est déplacé avant validation. Chaque déplacement vers le Lexar se fait par copie, vérification, puis suppression de l'original. Les dossiers ouverts sont refusés (garde-fou `lsof`).

## Lexar — structure proposée

| Nouveau dossier | Ce qui y va | Taille |
|---|---|---|
| `Cours/IPT/` | `IPT/CLionProjects`, `IPT/GSI`, `IPT/VSCODE`, `IPT/androidstudioproject` | ~0,3 Go |
| `Machines virtuelles/` | `IPT/UTM/GSI-Servidor.utm`, `IPT/UTM/Win11-ARM.utm`, `IPT/UTM/Snapshots`, `06 - antes-gpo.utm`, **les 3 VM UTM du Mac** | ~150 Go |
| `Machines virtuelles/ISO et installeurs/` | ISO Ubuntu (desktop + server), Windows 11, Windows Server 2025, `UTM.dmg` | ~20 Go |
| `Jeux/` | `Gaming/*` (Jeux RETRO, Minecraft.app, Pokémon Unbound, cobblemon), `cliente-thal-mods.zip`, `RetroArch`, `IPT/win11/minecraft` | ~1 Go |
| `Projets/` | `Button`, `button2`, `pokerogue-bot`, `Perso/Projet/*` (AirSend, Onzer, Infinity RPG…) | ~81 Go |
| `Perso/Captures d’écran/` | les captures et enregistrements d'écran qui traînent à la racine de `Perso` | ~40 Go |
| `Perso/Vidéos/` | `rubengameiro_c1547-mp4_2026-07-24_2039` | 7,9 Go |
| `Musique/` | inchangé (36 Go) | — |
| `Sauvegardes/` | `Pad 6 backup`, `Archives`, `Android` (data/media) | ~25 Go |
| `Applis/` | `Visual Studio Code.app`, `Lexar Utility` | 2,2 Go |
| (supprimés) | `Movies`, `Music`, `Pictures` : vides (seulement des vignettes Android) | 0 |

`GoSaver Outre-mer` et `GoSaver Lazaret` restent tels quels.

## Mac — ce qui bouge

| Élément | Destination | Gain sur le Mac |
|---|---|---|
| 3 VM UTM (`TPSI-Ubuntu-Desktop 2`, `… antes`, `TPSI-Ubuntu-Server`) | Lexar `Machines virtuelles/`, puis ouvertes dans UTM depuis le Lexar | **29 Go** |
| Cours dans Téléchargements (`Aula0x_GSI…`, `lab2/lab3…pdf`, `TPSI TH…`, `.pbix` Adventure Works / RH, `colaboradores_gsi.csv`) | `~/Documents/IPT/cours-2026-2027/<matière>` (année en cours : reste sur le Mac) | — |
| Doublons `… (1).docx/.pbix/.xlsx` | Lazaret (récupérables 30 jours) | petit |
| `pi2-2026-uniportal-main`, `pokerogue-bot-claude-…` | `~/Developer/` | — |
| `OP Auto Clicker.app` | `/Applications` | — |
| `photo_carlos.jpg`, notes `.md` | `~/Documents/Perso/` | — |
| Dossiers vides `Pour Avions`, `Roms` | supprimés | 0 |
| `Documents/capture` (190 Mo, 332 fichiers) | Lexar `Perso/Captures d’écran/` ; le dossier reste comme repli | 0,2 Go |

## À trancher

1. Captures d'écran automatiques : voir la réponse dans la conversation.
2. Les cours de l'année en cours restent sur le Mac (accès rapide) ; les années passées vont sur le Lexar.
