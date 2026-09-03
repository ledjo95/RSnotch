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

    /// Largeur reelle du panneau, mesuree plutot que recalculee depuis
    /// `NotchRootView` — deux calculs paralleles d'une meme grandeur finissent
    /// toujours par diverger d'un cran (§ tabBar, exactement le bug qui a
    /// motive cette mesure directe).
    @State private var panelWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: Theme.Metrics.contentSpacing) {
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, Theme.Metrics.panelPadding)
        .padding(.horizontal, Theme.Metrics.panelHorizontalPadding)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { panelWidth = $0 }
    }

    // MARK: Barre d'onglets

    // Les onglets ne portent PAS de `glassEffectID` : ils vivent dans le meme
    // GlassEffectContainer que la coquille, et un identifiant les ferait
    // fusionner avec elle — ils perdraient alors leur etat selectionne. Le
    // morph est reserve aux formes qui apparaissent et disparaissent.
    //
    // Positionnement en TROIS ZONES ANCREES (leading a gauche, trailing a
    // droite, chacune a sa largeur intrinseque) plutot qu'un HStack a un seul
    // `Spacer` : dans un HStack normal ce Spacer s'etire correctement pour
    // pousser `trailing` jusqu'au bord, mais un ScrollView autour (tente une
    // premiere fois, voir l'historique git) casse cet etirement — le Spacer
    // n'a plus que la largeur intrinseque du contenu a occuper, jamais celle,
    // plus grande, du panneau reel, et `trailing` reste colle au centre au
    // lieu d'atteindre le bord droit visible sur la coquille.
    //
    // Chaque zone est alignee independamment sur toute la largeur du ZStack
    // (`.frame(maxWidth: .infinity, alignment:)`) : leading colle a gauche,
    // trailing colle a droite, quelle que soit la largeur reelle du panneau.
    // Le trou pour
    // l'encoche n'a donc plus besoin d'etre "reserve" par un Spacer — il
    // existe de facto entre les deux zones ancrees, sauf si elles se
    // recouvrent (panneau plus etroit que leur besoin combine), auquel cas la
    // zone concernee defile plutot que de passer sous le capot.
    private var tabBar: some View {
        ZStack {
            leadingTabGroup
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingTabGroup
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // 26 pt et non 22 : dans un panneau qui frole les 1400 pt de large, une
        // rangee de pastilles de 22 pt se lisait comme un detail oublie en haut
        // a gauche. La barre d'onglets est la seule navigation du panneau, elle
        // doit peser son poids.
        .frame(height: 26)
    }

    private var leadingTabGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotchTab.leading) { tab in
                    GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                        select(tab)
                    }
                }
            }
        }
        // Plafonne le groupe avant l'encoche : au-dela, il faudrait qu'il
        // chevauche le creux plutot que de defiler. Sans encoche physique
        // (barre simulee), rien ne le contraint.
        .frame(maxWidth: leadingMaxWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var trailingTabGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotchTab.trailing) { tab in
                    GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                        select(tab)
                    }
                }
            }
        }
        .frame(maxWidth: trailingMaxWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Largeur maximale du groupe de gauche avant qu'il n'atteigne l'encoche :
    /// la moitie du panneau MESURE (§ panelWidth), moins la moitie de
    /// l'encoche. `nil` (donc illimite) tant que rien n'a encore ete mesure,
    /// ou des qu'il n'y a pas d'encoche physique a eviter — le premier layout
    /// affiche alors la barre normalement le temps que la mesure arrive.
    private var leadingMaxWidth: CGFloat? {
        guard model.geometry.hasPhysicalNotch, panelWidth > 0 else { return nil }
        return max(panelWidth / 2 - model.geometry.notchSize.width / 2 - 8, 0)
    }

    private var trailingMaxWidth: CGFloat? {
        leadingMaxWidth
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
                calendar: calendar.availability,
                quote: settings.quoteText,
                widthScale: widgets.rowScale(
                    requested: settings.panelWidth.scale,
                    spacing: Theme.Metrics.contentSpacing,
                    appItemCount: launcher.items.count,
                    screenWidth: model.geometry.screenFrame.width
                ),
                openTimerTab: { select(.timer) },
                openCalendarTab: { select(.calendar) }
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
