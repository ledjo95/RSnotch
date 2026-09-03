import SwiftUI

// MARK: - ExpandedPanelView
/// Panneau ouvert : barre d'onglets en verre, puis la zone de contenu de
/// l'onglet actif. Phase 0 n'expose qu'un ecran d'etat ; chaque phase suivante
/// remplace un `case` du switch par sa vraie vue.
struct ExpandedPanelView: View {

    @Bindable var model: NotchViewModel
    @Bindable var widgets: WidgetsViewModel
    @Bindable var launcher: LaunchItemsViewModel
    @Bindable var countdown: TimerService
    @Bindable var nowPlaying: NowPlayingViewModel
    @Bindable var pocket: PocketStorageService
    let weather: WeatherService
    let calendar: CalendarService
    var settings: AppSettings = .shared
    /// Transmis aux vues d'onglet qui ont besoin de morpher avec la coquille
    /// (Phase 5 : minuteur replie ↔ deplie).
    let glassNamespace: Namespace.ID

    /// Proprietaire du service : ne vit et ne sonde le CPU que tant que ce
    /// panneau existe, et SystemStatsTabView le demarre/arrete lui-meme selon
    /// sa propre visibilite (§ SystemStatsTabView.onAppear/onDisappear).
    @State private var stats = SystemStatsService()

    /// Le popover "Plus" (§ moreMenu) est construit a la main plutot qu'avec
    /// `Menu` : le style systeme de `Menu` refusait le `.glassButton` (bouton
    /// habille par macOS, chevron impose) et, sous `.menuStyle(.borderlessButton)`,
    /// disparaissait purement et simplement — aucune combinaison essayee ne
    /// rendait un simple rond de verre coherent avec `GlassIconButton`.
    @State private var showsMoreMenu = false

    var body: some View {
        VStack(spacing: Theme.Metrics.contentSpacing) {
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, Theme.Metrics.panelPadding)
        .padding(.horizontal, Theme.Metrics.panelHorizontalPadding)
    }

    // MARK: Barre d'onglets

    // Les onglets ne portent PAS de `glassEffectID` : ils vivent dans le meme
    // GlassEffectContainer que la coquille, et un identifiant les ferait
    // fusionner avec elle — ils perdraient alors leur etat selectionne. Le
    // morph est reserve aux formes qui apparaissent et disparaissent.
    //
    // DEUX ICONES FIXES SEULEMENT (Accueil, Plus) plutot qu'une rangee qui
    // grandit avec chaque nouvel onglet. Les trois tentatives precedentes de
    // faire tenir toute la liste dans la largeur du panneau (Spacer central,
    // ScrollView, groupes ancres aux bords — voir l'historique git) ont toutes
    // fini par recroiser l'encoche physique d'une machine a l'autre : le vrai
    // probleme n'etait pas LA REPARTITION des icones, c'etait LEUR NOMBRE.
    // Une barre a deux elements ne peut plus jamais deborder ni chevaucher le
    // capot, quel que soit le nombre d'onglets ajoutes a l'avenir.
    private var tabBar: some View {
        HStack(spacing: 6) {
            GlassIconButton(tab: .home, isActive: model.selectedTab == .home) {
                select(.home)
            }

            moreButton

            Spacer(minLength: 0)
        }
        // 26 pt et non 22 : dans un panneau qui frole les 1400 pt de large, une
        // rangee de pastilles de 22 pt se lisait comme un detail oublie en haut
        // a gauche. La barre d'onglets est la seule navigation du panneau, elle
        // doit peser son poids.
        .frame(height: 26)
    }

    /// Bouton rond, identique a `GlassIconButton`, qui bascule le popover
    /// `moreMenuOverlay` — pas un `Menu` SwiftUI (voir `showsMoreMenu`).
    private var moreButton: some View {
        Button {
            withAnimation(Theme.Motion.morph) { showsMoreMenu.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .glassButton(isProminent: isNonHomeTabActive, tint: isNonHomeTabActive ? .white : nil)
        .accessibilityLabel("Plus")
        .popover(isPresented: $showsMoreMenu, arrowEdge: .top) {
            moreMenuContent
        }
    }

    /// Regroupe tous les onglets sauf Accueil dans une liste verticale de
    /// pastilles, au meme gabarit visuel que le reste de l'app plutot que le
    /// style de menu systeme de macOS.
    private var moreMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NotchTab.allCases.filter { $0 != .home }) { tab in
                Button {
                    showsMoreMenu = false
                    select(tab)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 20)
                        Text(tab.accessibilityLabel)
                            .font(Theme.Typography.body(13, weight: .medium))
                        Spacer(minLength: 12)
                    }
                    .foregroundStyle(model.selectedTab == tab ? Theme.Palette.ember : Theme.Palette.frost)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(minWidth: 190)
        .background(Theme.Palette.ink)
    }

    /// L'etat "actif" du bouton Plus reflete la selection courante des lors
    /// qu'elle n'est pas Accueil — comme les autres icones de la barre, il
    /// doit dire ou l'on se trouve, pas seulement ouvrir un menu.
    private var isNonHomeTabActive: Bool {
        model.selectedTab != .home
    }

    private func select(_ tab: NotchTab) {
        withAnimation(Theme.Motion.morph) { model.selectedTab = tab }
    }

    // MARK: Contenu

    @ViewBuilder
    private var tabContent: some View {
        switch model.selectedTab {
        case .home:
            WidgetRowView(
                model: widgets,
                launcher: launcher,
                countdown: countdown,
                nowPlaying: nowPlaying,
                weather: weather.availability,
                widthScale: widgets.rowScale(
                    requested: settings.panelWidth.scale,
                    spacing: Theme.Metrics.contentSpacing,
                    appItemCount: launcher.items.count,
                    screenWidth: model.geometry.screenFrame.width
                ),
                openTimerTab: { select(.timer) }
            )
        case .clipboard:
            ClipboardTabView()
        case .timer:
            TimerTabView(timer: countdown)
        case .tray:
            TrayTabView(
                pocket: pocket,
                launcher: launcher,
                finish: { destination in model.restoreTabAfterDrag(to: destination) },
                holdOpen: { model.holdOpen() },
                keepOpen: { model.dragActivity() }
            )
        case .calendar:
            CalendarTabView(service: calendar)
        case .stats:
            SystemStatsTabView(service: stats)
        case .pocket:
            PocketTabView(pocket: pocket)
        case .settings:
            QuickSettingsTabView()
        }
    }
}
