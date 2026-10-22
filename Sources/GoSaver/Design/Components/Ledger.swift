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
            if terrains.isEmpty {
                Text("Le registre se remplit pendant le relevé.")
                    .font(Typo.water)
                    .foregroundStyle(Ink.inkFaded)
                    .padding(.top, Space.s4)
            }
            ForEach(terrains, id: \.self) { terrain in
                section(terrain)
            }
        }
        .padding(Space.s5)
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
        .accessibilityElement(children: .combine)
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
