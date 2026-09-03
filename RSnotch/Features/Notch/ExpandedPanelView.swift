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
    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.leading) { tab in
                GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                    select(tab)
                }
            }

            Spacer(minLength: 0)

            ForEach(NotchTab.trailing) { tab in
                GlassIconButton(tab: tab, isActive: model.selectedTab == tab) {
                    select(tab)
                }
            }
        }
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
        case .pocket:
            PocketTabView(pocket: pocket)
        case .settings:
            QuickSettingsTabView()
        }
    }
}
