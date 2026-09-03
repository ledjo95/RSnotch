import SwiftUI

// MARK: - WidgetRowView
//
// Rangee de widgets du panneau. Hauteur commune, largeurs variables.
//
// Glisser-deposer : l'identifiant du widget circule en texte brut plutot que
// via un UTType exporte. Un type sur mesure imposerait une declaration dans
// l'Info.plist et une justification en App Review pour un echange qui ne quitte
// jamais la fenetre. Un depot venu de l'exterieur est simplement ignore, car
// son contenu ne correspond a aucun widget connu.

struct WidgetRowView: View {

    @Bindable var model: WidgetsViewModel
    @Bindable var launcher: LaunchItemsViewModel
    @Bindable var countdown: TimerService
    @Bindable var nowPlaying: NowPlayingViewModel
    let weather: WeatherAvailability
    /// Echelle issue du reglage de largeur du panneau.
    var widthScale: CGFloat = 1
    let openTimerTab: () -> Void
    let openStatsTab: () -> Void

    @State private var targetedID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Metrics.contentSpacing) {
                if model.widgets.isEmpty {
                    emptyRow
                } else {
                    ForEach(model.widgets) { widget in
                        card(for: widget)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .contextMenu { rowMenu }
    }

    /// Rangee vide : sans elle, retirer le dernier widget rendrait le menu
    /// d'ajout inatteignable.
    private var emptyRow: some View {
        GlassCard {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .medium))
                Text("Clic droit pour ajouter un widget")
                    .font(Theme.Typography.body(11))
            }
            .foregroundStyle(Theme.Palette.mist)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
        }
        .frame(width: Theme.Metrics.defaultContentWidth * widthScale)
        .contextMenu { rowMenu }
    }

    // MARK: Carte

    private func card(for widget: PanelWidget) -> some View {
        // La pochette de musique occupe tout le fond de la carte, et le
        // widget peint lui-meme son repli quand il n'y en a pas.
        GlassCard(imageBleed: widget.kind == .music) {
            content(for: widget)
        }
        .frame(width: widget.displayWidth(appItemCount: launcher.items.count, scale: widthScale))
        .overlay {
            // Repere de depot : un liseré ambre sur la carte devant laquelle
            // l'element viendra s'inserer.
            if targetedID == widget.id {
                RoundedRectangle(
                    cornerRadius: Theme.Metrics.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(Theme.Palette.ember, lineWidth: 2)
            }
        }
        // L'apercu de glissement ne doit produire AUCUN effet de bord : muter un
        // `@State` depuis ce closure declenche une boucle d'invalidation qui fige
        // le rendu du panneau sans provoquer de crash — donc sans rien pour la
        // signaler. L'apercu se contente de reprendre la carte.
        .draggable(widget.id.uuidString) {
            GlassCard { content(for: widget) }
                .frame(
                    width: widget.displayWidth(appItemCount: launcher.items.count, scale: widthScale),
                    height: 64
                )
        }
        .dropDestination(for: String.self) { items, _ in
            defer { targetedID = nil }
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            return model.move(id: id, before: widget)
        } isTargeted: { isTargeted in
            targetedID = isTargeted ? widget.id : nil
        }
        .contextMenu { cardMenu(for: widget) }
        .animation(Theme.Motion.morph, value: model.widgets)
    }

    // MARK: Routage du contenu

    @ViewBuilder
    private func content(for widget: PanelWidget) -> some View {
        switch widget.kind {
        case .weather:
            WeatherWidgetView(availability: weather)
        case .apps:
            AppsWidgetView(model: launcher, size: widget.size)
        case .music:
            MusicWidgetView(model: nowPlaying, size: widget.size)
        case .timer:
            TimerWidgetView(timer: countdown, openTimerTab: openTimerTab)
        case .stats:
            SystemStatsWidgetView(size: widget.size, openStatsTab: openStatsTab)
        }
    }

    // MARK: Menus

    // Le menu de carte porte AUSSI l'ajout et la reinitialisation : le panneau
    // se cale desormais sur la largeur du contenu, il n'y a donc plus de fond
    // vide sur lequel faire un clic droit. Le menu de la rangee ne servirait
    // qu'a une rangee vide.
    @ViewBuilder
    private func cardMenu(for widget: PanelWidget) -> some View {
        let sizes = widget.kind.allowedSizes
        if sizes.count > 1 {
            Picker("Taille", selection: sizeBinding(for: widget)) {
                ForEach(sizes) { size in
                    Text(size.label).tag(size)
                }
            }
            Divider()
        }
        addMenu
        Divider()
        Button("Retirer \(widget.kind.title)", systemImage: "trash", role: .destructive) {
            withAnimation(Theme.Motion.morph) { model.remove(widget) }
        }
        Button("Réinitialiser la disposition", systemImage: "arrow.counterclockwise") {
            withAnimation(Theme.Motion.morph) { model.resetToDefaults() }
        }
    }

    @ViewBuilder
    private var rowMenu: some View {
        addMenu
        Button("Réinitialiser la disposition", systemImage: "arrow.counterclockwise") {
            withAnimation(Theme.Motion.morph) { model.resetToDefaults() }
        }
    }

    @ViewBuilder
    private var addMenu: some View {
        let available = model.availableKinds
        if available.isEmpty {
            Text("Tous les widgets sont affichés")
        } else {
            Menu("Ajouter un widget") {
                ForEach(available) { kind in
                    Button(kind.title, systemImage: kind.symbolName) {
                        withAnimation(Theme.Motion.morph) { model.add(kind) }
                    }
                }
            }
        }
    }

    private func sizeBinding(for widget: PanelWidget) -> Binding<WidgetSize> {
        Binding(
            get: { widget.size },
            set: { newSize in
                withAnimation(Theme.Motion.morph) { model.resize(widget, to: newSize) }
            }
        )
    }
}
