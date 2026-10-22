import SwiftUI
import GoSaverCore

/// Registre : le panneau latéral qui liste les terrains et leurs lieux
/// (docs/DESIGN_SYSTEM.md §6.6). Filets fins, cotes alignées à droite, pas de barre d'accent.
struct Ledger: View {
    let model: AtlasModel
    /// Nombre de lieux montrés par terrain avant « et N autres ».
    var placesPerTerrain = 4

    private var terrains: [Terrain] {
        Terrain.allCases
            .filter { model.bytes(of: $0) > 0 }
            .sorted { model.bytes(of: $0) > model.bytes(of: $1) }
    }

    var body: some View {
        // ImageRenderer (mode instantané) ne dessine pas le contenu d'un ScrollView.
        if Snapshot.isActive {
            content.fixedSize(horizontal: false, vertical: true).frame(maxHeight: .infinity, alignment: .top).clipped().modifier(Sheet())
        } else {
            ScrollView { content }.scrollIndicators(.never).modifier(Sheet())
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
            Text("Registre").regionStyle().foregroundStyle(Ink.inkFaded)
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
                Text("Le registre se remplit pendant le relevé.")
                    .font(Typo.water)
                    .foregroundStyle(Ink.inkFaded)
                    .padding(.top, Space.s4)
            }
            ForEach(terrains, id: \.self) { terrain in
                section(terrain)
            }
            outremer
        }
        .padding(Space.s5)
    }

    /// L'autre continent : ce qui est déjà parti sur le disque externe, et comment le rapatrier.
    @ViewBuilder
    private var outremer: some View {
        if let harbor = model.harborVolume {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Outre-mer").font(Typo.heading).foregroundStyle(Ink.ink)
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
                    HStack(spacing: Space.s2) {
                        Text(URL(fileURLWithPath: record.original).lastPathComponent)
                            .font(Typo.body).foregroundStyle(Ink.ink).lineLimit(1)
                        if record.linked { Text("lien").font(Typo.label).foregroundStyle(Ink.sea) }
                        Spacer(minLength: Space.s2)
                        Text(Bytes.format(record.bytes)).font(Typo.figure).foregroundStyle(Ink.inkFaded)
                        Button("Rapatrier") { model.prepareReturn(record) }
                            .buttonStyle(NoteButtonStyle())
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.top, Space.s4)
        }
    }

    /// Visible dès l'ouverture tant que l'accès complet au disque manque.
    private var accessNotice: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Zones fermées").font(Typo.heading).foregroundStyle(Ink.ink)
            Text("Sans l’accès complet au disque, la corbeille et certains dossiers restent dans le brouillard.")
                .font(Typo.label).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ouvrir l’accès") { model.accessSheetOpen = true }
                .buttonStyle(TraceButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s4)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.contour).frame(height: Stroke.hairline) }
    }

    @ViewBuilder
    private func section(_ terrain: Terrain) -> some View {
        let places = model.landmarks(of: terrain)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                TerrainSwatch(terrain: terrain)
                    .frame(width: 22, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(terrain.name).font(Typo.heading).foregroundStyle(Ink.ink)
                    Text(terrain.meaning).font(Typo.label).foregroundStyle(Ink.inkFaded)
                }
                Spacer(minLength: Space.s2)
                Text(Bytes.format(model.bytes(of: terrain)))
                    .font(Typo.figure)
                    .foregroundStyle(Ink.ink)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, Space.s3)

            // Massif : on dit franchement ce qui n'a pas pu être relevé, et comment l'ouvrir.
            if terrain == .massif, model.diskAccess != .granted, let denied = model.survey?.deniedPaths.count, denied > 0 {
                Text("Comprend \(denied) dossiers fermés au géomètre.")
                    .font(Typo.label).foregroundStyle(Ink.inkFaded)
                    .padding(.leading, 22 + Space.s3)
                    .padding(.bottom, Space.s2)
            }
            ForEach(places.prefix(placesPerTerrain)) { place in
                Button {
                    model.toggleSelection(place.id)
                } label: {
                    row(place.title, Bytes.format(place.bytes),
                        selected: model.selectedID == place.id,
                        hovered: model.hoveredID == place.id)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedID == place.id ? .isSelected : [])
                .accessibilityHint("Montre ce lieu sur la carte")
            }
            if places.count > placesPerTerrain {
                let rest = places.dropFirst(placesPerTerrain).reduce(Int64(0)) { $0 + $1.bytes }
                row("et \(places.count - placesPerTerrain) autres lieux", Bytes.format(rest), faded: true)
            }
            Rectangle().fill(Ink.contour).frame(height: Stroke.hairline)
                .padding(.top, Space.s2)
        }
        // « contain » et non « combine » : chaque lieu reste un bouton distinct pour VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(terrain.name), \(terrain.meaning), \(Bytes.format(model.bytes(of: terrain)))")
    }

    private func row(_ name: String, _ figure: String?, faded: Bool = false,
                     selected: Bool = false, hovered: Bool = false) -> some View {
        HStack(spacing: Space.s2) {
            Text(name)
                .font(faded ? Typo.water : (selected ? Typo.bodyStrong : Typo.body))
                .foregroundStyle(faded ? Ink.inkFaded : Ink.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.s2)
            if let figure {
                Text(figure).font(Typo.figure).foregroundStyle(Ink.inkFaded)
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
