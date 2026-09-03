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
    // HStack simple avec un unique Spacer — le comportement natif SwiftUI le
    // plus previsible pour pousser un groupe a gauche et l'autre a droite.
    // Aucun ScrollView autour tant qu'il n'est pas necessaire : les deux
    // tentatives precedentes (Spacer(minLength:) dans un ScrollView, puis
    // ZStack de deux ScrollView) cassaient chacune l'etirement naturel du
    // Spacer d'une facon differente et non reproduite en local (voir
    // l'historique git) — la cause exacte n'a jamais ete confirmee avec
    // certitude sur la machine ou le bug se voit, donc on revient a la forme
    // la plus simple possible, celle dont le comportement est garanti par
    // SwiftUI lui-meme plutot que reconstruit a la main.
    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.leading) { tab in
                GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                    select(tab)
                }
            }

            // L'ENCOCHE PHYSIQUE PASSE ICI (§ NotchGeometry.tabBarNotchGap).
            // La barre occupe la premiere ligne du panneau, exactement la
            // bande que le capot occulte : sans ce minimum, une icone qui
            // tombe au centre disparaitrait derriere lui.
            Spacer(minLength: model.geometry.tabBarNotchGap)

            ForEach(NotchTab.trailing) { tab in
                GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                    select(tab)
                }
            }
        }
        .frame(maxWidth: .infinity)
        // 26 pt et non 22 : dans un panneau qui frole les 1400 pt de large, une
        // rangee de pastilles de 22 pt se lisait comme un detail oublie en haut
        // a gauche. La barre d'onglets est la seule navigation du panneau, elle
        // doit peser son poids.
        .frame(height: 26)
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
