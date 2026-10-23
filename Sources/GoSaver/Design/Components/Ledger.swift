import SwiftUI
import GoSaverCore

/// Registre : le panneau latéral qui liste les terrains et leurs lieux
/// (docs/DESIGN_SYSTEM.md §6.6). Filets fins, cotes alignées à droite, pas de barre d'accent.
struct Ledger: View {
    let model: AtlasModel
    /// Nombre de lieux montrés par terrain avant « et N autres ».
    var placesPerTerrain = 4
    /// Nombre de lieux affichés par terrain quand on a déplié la liste.
    @State private var shown: [Terrain: Int] = [:]

    private var terrains: [Terrain] {
        Terrain.allCases
            .filter { $0 != .ruins && model.bytes(of: $0) > 0 }
            .sorted { model.bytes(of: $0) > model.bytes(of: $1) }
    }

    var body: some View {
        // ImageRenderer (mode instantané) ne dessine pas le contenu d'un ScrollView.
        if Snapshot.isActive {
            content.fixedSize(horizontal: false, vertical: true).frame(maxHeight: .infinity, alignment: .top).clipped().modifier(Sheet())
        } else {
            ScrollView { content }.scrollIndicators(.never).modifier(Sheet())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.selecting, !model.picked.isEmpty { BatchBar(model: model) }
                }
        }
    }

    /// Feuille du registre : papier relevé, filet d'encre côté carte.
    private struct Sheet: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(Ink.paperRaised)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Ink.ink).frame(width: Stroke.rule)
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Words.ledger).regionStyle().foregroundStyle(Ink.inkFaded)
                Spacer()
                if model.phase == .surveyed {
                    Button(model.selecting ? "Terminer" : "Sélectionner") {
                        withAnimation(Motion.settle) {
                            if model.selecting { model.endSelection() } else { model.selecting = true; model.selectedID = nil }
                        }
                    }
                    .buttonStyle(NoteButtonStyle())
                }
            }
            .padding(.bottom, Space.s2)
            GraduatedRule()
            if model.diskAccess == .denied {
                accessNotice
            } else if model.diskAccess == .granted {
                // Retour visible : sans lui, le bloc « Zones fermées » disparaissait sans explication.
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Path { p in
                        p.move(to: CGPoint(x: 1, y: 6)); p.addLine(to: CGPoint(x: 4.5, y: 9.5)); p.addLine(to: CGPoint(x: 11, y: 2))
                    }
                    .stroke(Ink.forest, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 11)
                    Text("Accès complet au disque accordé").font(Typo.label).foregroundStyle(Ink.forest)
                }
                .padding(.top, Space.s3)
            }
            if terrains.isEmpty {
                Text(Words.atlas ? "Le registre se remplit pendant le relevé." : "Le détail apparaît pendant l’analyse.")
                    .font(Typo.water)
                    .foregroundStyle(Ink.inkFaded)
                    .padding(.top, Space.s4)
            }
            if !model.visibleRuins.isEmpty { ruinsSection }
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(terrains, id: \.self) { terrain in
                    Section {
                        section(terrain)
                    } header: {
                        sectionHeader(terrain)
                    }
                }
            }
            if model.harborVolume == nil, !model.brokenLinks.isEmpty { brokenLinksWarning }
            outremer
            lazaret
        }
        .padding(Space.s5)
    }

    /// Disque débranché alors que des dossiers liés y vivent : on le dit, avec leurs noms.
    private var brokenLinksWarning: some View {
        let names = model.brokenLinks.map { URL(fileURLWithPath: $0).lastPathComponent }
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(Words.atlas ? "Liaison rompue" : "Disque externe débranché").regionStyle().foregroundStyle(Ink.ochre)
            Text("\(names.count) dossier\(names.count > 1 ? "s liés sont" : " lié est") inaccessible\(names.count > 1 ? "s" : "") tant que le disque externe n’est pas rebranché : \(names.prefix(5).joined(separator: ", "))\(names.count > 5 ? "…" : ""). Les applis qui s’en servent peuvent signaler une erreur ; rien n’est perdu.")
                .font(Typo.label).foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s5)
        .accessibilityElement(children: .combine)
    }

    /// L'autre continent : ce qui est déjà parti sur le disque externe, et comment le rapatrier.
    @ViewBuilder
    private var outremer: some View {
        if let harbor = model.harborVolume {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.outremer).font(Typo.heading).foregroundStyle(Ink.ink)
                        Text("\(harbor.name) · \(harbor.format.label) · \(Bytes.format(harbor.freeBytes)) libres")
                            .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    }
                    Spacer()
                    if !model.convoys.isEmpty {
                        Text(Bytes.format(model.convoys.reduce(Int64(0)) { $0 + $1.bytes }))
                            .font(Typo.figure).foregroundStyle(Ink.sea)
                    }
                }
                .padding(.vertical, Space.s3)
                if model.convoys.isEmpty {
                    Text("Aucun convoi pour l’instant. Ouvre la fiche d’un lieu pour l’envoyer ici.")
                        .font(Typo.water).foregroundStyle(Ink.inkFaded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.convoys) { record in
                    convoyRow(record, on: harbor)
                }
            }
            .padding(.top, Space.s4)
        }
    }

    /// Ruines : ce que l'expertise a trouvé, en tête du registre (c'est là qu'on agit en premier).
    private var ruinsSection: some View {
        let safe = model.safeRuins
        let safeBytes = safe.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                TerrainSwatch(terrain: .ruins)
                    .frame(width: 22, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.terrain(.ruins)).font(Typo.heading).foregroundStyle(Ink.ink)
                    Text("\(model.visibleRuins.count) trouvaille\(model.visibleRuins.count > 1 ? "s" : "") \(Words.atlas ? "de l’expertise" : "à vérifier")")
                        .font(Typo.label).foregroundStyle(Ink.inkFaded)
                }
                Spacer(minLength: Space.s2)
                Text(Bytes.format(model.visibleRuins.reduce(Int64(0)) { $0 + $1.bytes }))
                    .font(Typo.figure).foregroundStyle(Ink.ink)
            }
            .padding(.vertical, Space.s3)

            ForEach(model.visibleRuins.prefix(8)) { ruin in
                Button { if model.selecting { model.togglePick(ruin.id) } else { model.toggleSelection(ruin.id) } } label: {
                    HStack(spacing: Space.s2) {
                        if model.selecting {
                            Image(systemName: model.picked.contains(ruin.id) ? "xmark.square" : "square")
                                .foregroundStyle(model.picked.contains(ruin.id) ? Ink.vermilion : Ink.ink)
                                .padding(.leading, -(13 + Space.s2))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ruin.kind == .orphanAppData ? ruinTitle(ruin) : ruin.url.lastPathComponent)
                                .font(model.selectedID == ruin.id ? Typo.bodyStrong : Typo.body)
                                .foregroundStyle(Ink.ink).lineLimit(1).truncationMode(.middle)
                            Text(ruin.kind.label).font(Typo.label).foregroundStyle(Ink.inkFaded)
                        }
                        Spacer(minLength: Space.s2)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Bytes.format(ruin.bytes)).font(Typo.figure).foregroundStyle(Ink.inkFaded)
                            Text(ruin.verdict == .isolate ? "à isoler" : "à examiner")
                                .font(Typo.label).foregroundStyle(ruin.verdict == .isolate ? Ink.vermilion : Ink.ochre)
                        }
                    }
                    .padding(.leading, 22 + Space.s3)
                    .padding(.vertical, 3)
                    .background(model.selectedID == ruin.id || model.picked.contains(ruin.id) ? Ink.paperSunken : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.visibleRuins.count > 8 {
                Text("et \(model.visibleRuins.count - 8) autres").font(Typo.water).foregroundStyle(Ink.inkFaded)
                    .padding(.leading, 22 + Space.s3)
            }
            if !safe.isEmpty, model.harborVolume != nil {
                Button("Isoler les \(safe.count) ruines sûres (\(Bytes.format(safeBytes)))") { model.prepareQuarantineRuins() }
                    .buttonStyle(TraceButtonStyle())
                    .padding(.leading, 22 + Space.s3)
                    .padding(.vertical, Space.s2)
            }
            Rectangle().fill(Ink.contour).frame(height: Stroke.hairline).padding(.top, Space.s2)
        }
        .accessibilityElement(children: .contain)
    }

    private func ruinTitle(_ ruin: Ruin) -> String {
        PlaceNames.display(raw: ruin.url.lastPathComponent)
    }

    /// Le Lazaret : la corbeille du disque externe, avec le temps qu'il reste à chaque élément.
    @ViewBuilder
    private var lazaret: some View {
        if let harbor = model.harborVolume {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.lazaret).font(Typo.heading).foregroundStyle(Ink.ink)
                        Text("Corbeille de \(harbor.name) · vidée après 30 jours").font(Typo.label).foregroundStyle(Ink.inkFaded)
                    }
                    Spacer()
                    if !model.lazaretEntries.isEmpty {
                        Text(Bytes.format(model.lazaretEntries.reduce(Int64(0)) { $0 + $1.bytes }))
                            .font(Typo.figure).foregroundStyle(Ink.ochre)
                    }
                }
                .padding(.vertical, Space.s3)
                if !model.lastPurge.isEmpty {
                    Text("\(model.lastPurge.count) élément\(model.lastPurge.count > 1 ? "s ont" : " a") atteint ses 30 jours et \(model.lastPurge.count > 1 ? "ont été supprimés" : "a été supprimé").")
                        .font(Typo.label).foregroundStyle(Ink.inkFaded)
                        .padding(.bottom, Space.s2)
                }
                if model.lazaretEntries.isEmpty {
                    Text("Vide. Depuis la fiche d’un lieu, « \(Words.toLazaret) » y envoie ce dont tu ne veux plus.")
                        .font(Typo.water).foregroundStyle(Ink.inkFaded)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.lazaretEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.s2) {
                            Text(URL(fileURLWithPath: entry.original).lastPathComponent)
                                .font(Typo.body).foregroundStyle(Ink.ink).lineLimit(1)
                            Spacer(minLength: Space.s2)
                            Text(Bytes.format(entry.bytes)).font(Typo.figure).foregroundStyle(Ink.inkFaded)
                        }
                        HStack(spacing: Space.s2) {
                            let days = entry.daysLeft()
                            Text(days <= 1 ? "supprimé demain" : "encore \(days) jours")
                                .font(Typo.label).foregroundStyle(days <= 3 ? Ink.ochre : Ink.inkFaded)
                            Spacer(minLength: Space.s2)
                            Button("Restaurer") { model.prepareRestore(entry) }.buttonStyle(NoteButtonStyle())
                            Button("Supprimer") { model.prepareDiscard(entry) }.buttonStyle(NoteButtonStyle())
                        }
                    }
                    .padding(.vertical, Space.s1)
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.top, Space.s4)
        }
    }

    /// Un envoi : son nom, où il se trouve sur le disque, et ce qu'on peut en faire.
    /// Encore dans le dossier d'accueil → « à ranger » ; déjà rangé → son rayonnage.
    private func convoyRow(_ record: Convoy.Record, on harbor: TargetVolume) -> some View {
        let shelf = AtlasModel.shelfName(record, on: harbor)
        let waiting = shelf == "GoSaver Outre-mer" || shelf.hasPrefix("GoSaver Outre-mer/")
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.s2) {
                Text(URL(fileURLWithPath: record.original).lastPathComponent)
                    .font(Typo.body).foregroundStyle(Ink.ink).lineLimit(1)
                if record.linked { Text("lien").font(Typo.label).foregroundStyle(Ink.sea) }
                Spacer(minLength: Space.s2)
                Text(Bytes.format(record.bytes)).font(Typo.figure).foregroundStyle(Ink.inkFaded)
            }
            HStack(spacing: Space.s2) {
                if waiting {
                    Text("à ranger").font(Typo.label).foregroundStyle(Ink.ochre)
                } else {
                    Text("dans \(shelf)\(record.mergedItems != nil ? " (fusionné)" : "")")
                        .font(Typo.label).foregroundStyle(Ink.inkFaded)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: Space.s2)
                if record.mergedItems == nil {
                    Button(waiting ? "Ranger" : "Déplacer") { model.prepareRelocate(record) }
                        .buttonStyle(NoteButtonStyle())
                }
                Button("Rapatrier") { model.prepareReturn(record) }
                    .buttonStyle(NoteButtonStyle())
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(URL(fileURLWithPath: record.original).lastPathComponent), \(waiting ? "à ranger" : "dans \(shelf)")")
    }

    /// Visible dès l'ouverture tant que l'accès complet au disque manque.
    private var accessNotice: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(Words.closedZones).font(Typo.heading).foregroundStyle(Ink.ink)
            Text(Words.hiddenWithoutAccess)
                .font(Typo.label).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ouvrir l’accès") { model.accessSheetOpen = true }
                .buttonStyle(TraceButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s4)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.contour).frame(height: Stroke.hairline) }
    }

    /// En-tête d'un terrain : reste collé en haut du registre pendant qu'on fait défiler ses lieux.
    private func sectionHeader(_ terrain: Terrain) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                TerrainSwatch(terrain: terrain)
                    .frame(width: 22, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.terrain(terrain)).font(Typo.heading).foregroundStyle(Ink.ink)
                    Text(Words.terrainDetail(terrain)).font(Typo.label).foregroundStyle(Ink.inkFaded)
                }
                Spacer(minLength: Space.s2)
                Text(Bytes.format(model.bytes(of: terrain)))
                    .font(Typo.figure)
                    .foregroundStyle(Ink.ink)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, Space.s3)
        .background(Ink.paperRaised)
    }

    @ViewBuilder
    private func section(_ terrain: Terrain) -> some View {
        let places = model.landmarks(of: terrain)
        VStack(alignment: .leading, spacing: 0) {
            if model.selecting, !places.isEmpty {
                // « Tout » coche les lieux affichés de la section (pas ceux encore repliés).
                let visible = places.prefix(shown[terrain] ?? placesPerTerrain).map(\.id)
                let all = !visible.isEmpty && visible.allSatisfy(model.picked.contains)
                Toggle(isOn: Binding(get: { all }, set: { model.setPicked(Array(visible), $0) })) {
                    Text("tout ce qui est affiché").font(Typo.label).foregroundStyle(Ink.inkFaded)
                }
                .toggleStyle(SurveyCheckboxStyle())
                .padding(.leading, 22 + Space.s3)
                .padding(.bottom, Space.s1)
            }

            // Massif : on dit franchement ce qui n'a pas pu être relevé, et comment l'ouvrir.
            if terrain == .massif, model.diskAccess != .granted, let denied = model.survey?.deniedPaths.count, denied > 0 {
                Text(Words.atlas ? "Comprend \(denied) dossiers fermés au géomètre." : "Comprend \(denied) dossiers protégés non analysés.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .padding(.leading, 22 + Space.s3)
                    .padding(.bottom, Space.s2)
            }
            let limit = shown[terrain] ?? placesPerTerrain
            ForEach(places.prefix(limit)) { place in
                Button {
                    if model.selecting { model.togglePick(place.id) } else { model.toggleSelection(place.id) }
                } label: {
                    row(place.title, Bytes.format(place.bytes), subtitle: place.subtitle,
                        selected: model.selecting ? model.picked.contains(place.id) : model.selectedID == place.id,
                        hovered: model.hoveredID == place.id,
                        checkbox: model.selecting ? model.picked.contains(place.id) : nil)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedID == place.id ? .isSelected : [])
                .accessibilityHint(model.selecting ? "Coche ou décoche ce lieu" : "Montre ce lieu sur la carte")
            }
            // « et N autres lieux » se déplie par paquets de 50, du plus gros au plus petit.
            HStack(spacing: Space.s3) {
                if places.count > limit {
                    let rest = places.dropFirst(limit).reduce(Int64(0)) { $0 + $1.bytes }
                    Button {
                        withAnimation(Motion.settle) { shown[terrain] = limit + 50 }
                    } label: {
                        row("et \(places.count - limit) autres · afficher", Bytes.format(rest), faded: true)
                    }
                    .buttonStyle(.plain)
                }
                if limit > placesPerTerrain {
                    Button("Replier") { withAnimation(Motion.settle) { shown[terrain] = nil } }
                        .buttonStyle(NoteButtonStyle())
                }
            }
            Rectangle().fill(Ink.contour).frame(height: Stroke.hairline)
                .padding(.top, Space.s2)
        }
        // « contain » et non « combine » : chaque lieu reste un bouton distinct pour VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Words.terrain(terrain)), \(Words.terrainDetail(terrain)), \(Bytes.format(model.bytes(of: terrain)))")
    }

    private func row(_ name: String, _ figure: String?, subtitle: String? = nil, faded: Bool = false,
                     selected: Bool = false, hovered: Bool = false, checkbox: Bool? = nil) -> some View {
        HStack(spacing: Space.s2) {
            if let checkbox {
                // Case de registre : carré d'encre, croix vermillon quand elle est cochée.
                ZStack {
                    Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.rule)
                    if checkbox {
                        Path { p in
                            p.move(to: CGPoint(x: 3, y: 3)); p.addLine(to: CGPoint(x: 10, y: 10))
                            p.move(to: CGPoint(x: 10, y: 3)); p.addLine(to: CGPoint(x: 3, y: 10))
                        }
                        .stroke(Ink.vermilion, lineWidth: 1.5)
                    }
                }
                .frame(width: 13, height: 13)
                .padding(.leading, -(13 + Space.s2))
            }
            Text(name)
                .font(faded ? Typo.water : (selected ? Typo.bodyStrong : Typo.body))
                .foregroundStyle(faded ? Ink.inkFaded : Ink.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            // Précision pour les homonymes et les noms génériques (« Messages · Bibliothèque »).
            if let subtitle {
                Text(subtitle).font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: Space.s2)
            // La taille ne se coupe jamais : c'est le nom et la précision qui cèdent la place.
            if let figure {
                Text(figure).font(Typo.figure).foregroundStyle(Ink.inkFaded)
                    .fixedSize().layoutPriority(2)
            }
        }
        .padding(.leading, 22 + Space.s3)
        .padding(.vertical, 3)
        // Sélection : fond en creux, comme une ligne soulignée au crayon dans un registre.
        .background(alignment: .leading) {
            if selected || hovered {
                Rectangle()
                    .fill(selected ? Ink.paperSunken : Ink.paperSunken.opacity(0.5))
                    .padding(.leading, 22 + Space.s1)
                    .padding(.horizontal, -Space.s1)
            }
        }
        .contentShape(Rectangle())
        .animation(Motion.quick, value: selected)
    }
}

/// Barre d'actions de la sélection : nombre, taille, et les actions possibles sur tout le lot.
struct BatchBar: View {
    let model: AtlasModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(model.picked.count) sélectionné\(model.picked.count > 1 ? "s" : "")")
                    .font(Typo.bodyStrong).foregroundStyle(Ink.ink)
                Text(Bytes.format(model.pickedBytes)).font(Typo.figure).foregroundStyle(Ink.ink)
                Spacer()
                Button("Tout décocher") { model.picked = [] }.buttonStyle(NoteButtonStyle())
            }
            HStack(spacing: Space.s2) {
                Button("Supprimer") { model.prepareBatch(.trash) }
                    .buttonStyle(TraceButtonStyle()).fixedSize()
                    .help("Corbeille de macOS (les applis avec leurs restes)")
                if model.harborVolume != nil {
                    Button(Words.atlas ? "Outre-mer" : "Déplacer") { model.prepareBatch(.outremer) }
                        .buttonStyle(TraceButtonStyle()).fixedSize()
                        .help("Envoyer sur le disque externe")
                    Button(Words.atlas ? "Lazaret" : "Isoler") { model.prepareBatch(.lazaret) }
                        .buttonStyle(TraceButtonStyle()).fixedSize()
                        .help("Corbeille du disque externe, vidée automatiquement")
                }
            }
        }
        .padding(Space.s4)
        .background(Ink.paperRaised)
        .overlay(alignment: .top) { Rectangle().fill(Ink.ink).frame(height: Stroke.rule) }
    }
}
