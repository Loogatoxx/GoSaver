import SwiftUI
import GoSaverCore

/// Feuille de confirmation de l'assèchement : ce qui part, ce qui reste, et pourquoi.
/// Rien n'est supprimé avant le clic sur le Sceau.
struct DrainSheet: View {
    @Bindable var model: AtlasModel

    var body: some View {
        ZStack {
            // Voile de papier : la carte reste devinable derrière.
            Ink.paper.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { if case .confirming = model.drainPhase { model.cancelDrain() } }

            VStack(alignment: .leading, spacing: Space.s4) {
                switch model.drainPhase {
                case .planning:
                    title("Relevé des marais…", subtitle: "On mesure ce qui peut partir. Rien n’est encore touché.")
                case .confirming:
                    confirming
                case .draining(let removed):
                    title("Assèchement en cours", subtitle: "Les applis recréeront leurs caches au besoin.")
                    Text(Bytes.format(removed))
                        .font(Typo.display).foregroundStyle(Ink.sea)
                        .contentTransition(.numericText())
                        .animation(Motion.quick, value: removed)
                    Text("rendus à la mer").font(Typo.water).foregroundStyle(Ink.inkFaded)
                case .done(let removed, let failures):
                    done(removed: removed, failures: failures)
                case .closed:
                    EmptyView()
                }
            }
            .padding(Space.s6)
            .frame(width: 480, alignment: .leading)
            .background(Ink.paperRaised.sheetShadow(lifted: true))
            .overlay(DoubleRule())
        }
    }

    // MARK: - Étapes

    @ViewBuilder
    private var confirming: some View {
        let plan = model.drainPlan
        title("Assécher les marais",
              subtitle: "Caches et journaux se reforment seuls : les applis les recréent quand elles en ont besoin.")

        VStack(spacing: 0) {
            ForEach([Drainer.Kind.cache, .log], id: \.self) { kind in
                row(kind.label, count: plan?.count(of: kind) ?? 0, bytes: plan?.bytes(of: kind) ?? 0)
            }
            trashRow(plan)
        }

        if let inUse = plan?.inUse, !inUse.isEmpty {
            let names = Array(Set(inUse.map { PlaceNames.display(raw: $0.owner) })).sorted().prefix(4)
            Text("Laissés en place car ouverts : \(names.joined(separator: ", ")). Ferme-les pour les assécher aussi.")
                .font(Typo.label).foregroundStyle(Ink.inkFaded)
                .fixedSize(horizontal: false, vertical: true)
        }

        GraduatedRule()

        let total = model.drainSelection.reduce(Int64(0)) { $0 + $1.bytes }
        HStack(alignment: .firstTextBaseline) {
            Text("Total").regionStyle().foregroundStyle(Ink.inkFaded)
            Spacer()
            Text(Bytes.format(total)).font(Typo.figureLarge).foregroundStyle(Ink.vermilion)
        }

        HStack(spacing: Space.s3) {
            Button("Annuler") { model.cancelDrain() }
                .buttonStyle(TraceButtonStyle())
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Assécher \(Bytes.format(total))") { model.confirmDrain() }
                .buttonStyle(SealButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(total == 0)
        }
        .padding(.top, Space.s2)
    }

    @ViewBuilder
    private func done(removed: Int64, failures: Int) -> some View {
        title("Marais asséchés", subtitle: nil)
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(Bytes.format(removed)).font(Typo.display).foregroundStyle(Ink.sea)
        }
        Text("rendus à la mer. La carte a été redessinée.")
            .font(Typo.water).foregroundStyle(Ink.inkFaded)
        if failures > 0 {
            Text("\(failures) élément\(failures > 1 ? "s" : "") n’\(failures > 1 ? "ont" : "a") pas pu être supprimé\(failures > 1 ? "s" : "") (protégé\(failures > 1 ? "s" : "") par macOS ou en cours d’usage). Ils restent en place.")
                .font(Typo.label).foregroundStyle(Ink.ochre)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("Fermer") { model.cancelDrain() }
                .buttonStyle(TraceButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Pièces

    private func title(_ text: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(text).font(Typo.title).foregroundStyle(Ink.ink)
            if let subtitle {
                Text(subtitle).font(Typo.water).foregroundStyle(Ink.inkFaded)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ label: String, count: Int, bytes: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(label).font(Typo.body).foregroundStyle(Ink.ink)
            Text(count == 1 ? "1 élément" : "\(count) éléments").font(Typo.label).foregroundStyle(Ink.inkFaded)
            Spacer()
            Text(Bytes.format(bytes)).font(Typo.figure).foregroundStyle(Ink.ink)
        }
        .padding(.vertical, Space.s2)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.contour).frame(height: Stroke.hairline) }
    }

    @ViewBuilder
    private func trashRow(_ plan: Drainer.Plan?) -> some View {
        let unreadable = plan?.unreadable.contains(.trash) == true
        let bytes = plan?.bytes(of: .trash) ?? 0
        VStack(alignment: .leading, spacing: Space.s1) {
            Toggle(isOn: $model.includeTrash) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("Vider aussi la corbeille").font(Typo.body).foregroundStyle(Ink.ink)
                    Spacer()
                    Text(unreadable ? "—" : Bytes.format(bytes)).font(Typo.figure).foregroundStyle(Ink.ink)
                }
            }
            .toggleStyle(SurveyCheckboxStyle())
            .disabled(unreadable || bytes == 0)
            Text(unreadable
                 ? "Illisible sans l’accès complet au disque. Tu peux la vider depuis le Finder."
                 : "Définitif : ce qui est dans la corbeille ne pourra plus être récupéré.")
                .font(Typo.label)
                .foregroundStyle(unreadable ? Ink.inkFaded : Ink.ochre)
                .padding(.leading, 22)
        }
        .padding(.vertical, Space.s2)
    }
}

/// Case à cocher de registre : carré d'encre, croix de plume quand elle est cochée.
struct SurveyCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                ZStack {
                    Rectangle().strokeBorder(Ink.ink, lineWidth: Stroke.rule)
                    if configuration.isOn {
                        Path { p in
                            p.move(to: CGPoint(x: 3, y: 3)); p.addLine(to: CGPoint(x: 11, y: 11))
                            p.move(to: CGPoint(x: 11, y: 3)); p.addLine(to: CGPoint(x: 3, y: 11))
                        }
                        .stroke(Ink.vermilion, lineWidth: 1.6)
                    }
                }
                .frame(width: 14, height: 14)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
