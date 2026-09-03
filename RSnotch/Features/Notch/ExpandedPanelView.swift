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
    // FILET DE SECURITE : la barre est enveloppee dans un ScrollView horizontal
    // plutot que de compter sur un calcul de largeur de panneau toujours juste.
    // Deux sources d'etroitesse echappent a ce calcul — la largeur d'ecran reelle
    // (l'encoche varie d'un Mac a l'autre, un MacBook peut faire 1710 pt quand le
    // poste de developpement en fait 2880) et le nombre d'onglets, qui grandit a
    // chaque nouvelle fonctionnalite. Un ScrollView absorbe les deux cas sans
    // qu'aucun n'ait besoin d'etre anticipe individuellement : au pire, la barre
    // defile au lieu de deborder ou de passer sous le capot.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotchTab.leading) { tab in
                    GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                        select(tab)
                    }
                }

                // L'ENCOCHE PHYSIQUE PASSE ICI. La barre occupe la premiere
                // ligne du panneau, c'est-a-dire exactement la bande ou la
                // dalle est occultee : une icone qui tombe au centre disparait
                // derriere le capot, sans rien pour le signaler. Le creux est
                // donc reserve au milieu, comme la barre de menus de macOS le
                // fait pour ses propres elements.
                //
                // `minLength` et non une largeur fixe : sur un ecran sans
                // encoche le creux vaut zero et les deux groupes se repoussent
                // normalement ; dans un ScrollView un Spacer n'a plus de
                // largeur infinie a offrir, il retombe donc a son minimum et
                // les deux groupes se collent — c'est le ScrollView qui prend
                // le relais pour eviter tout chevauchement avec l'encoche.
                Spacer(minLength: model.geometry.tabBarNotchGap)

                ForEach(NotchTab.trailing) { tab in
                    GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                        select(tab)
                    }
                }
            }
            .frame(minWidth: scrollContentMinWidth)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // 26 pt et non 22 : dans un panneau qui frole les 1400 pt de large, une
        // rangee de pastilles de 22 pt se lisait comme un detail oublie en haut
        // a gauche. La barre d'onglets est la seule navigation du panneau, elle
        // doit peser son poids.
        .frame(height: 26)
    }

    /// Sans ce plancher, un `Spacer` dans un `ScrollView` s'ecrase a zero et le
    /// creux de l'encoche disparait purement et simplement — le ScrollView doit
    /// explicitement etre invite a etre AUSSI large que le besoin reel de la
    /// barre pour que le Spacer ait quelque chose a occuper.
    private var scrollContentMinWidth: CGFloat {
        Theme.Metrics.tabBarMinimumWidth(notchGap: model.geometry.tabBarNotchGap)
            - Theme.Metrics.panelHorizontalPadding * 2
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
