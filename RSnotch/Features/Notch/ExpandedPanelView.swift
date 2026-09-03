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
        // Le popover "Plus" (§ moreButton) est un OVERLAY, pas un `.popover`
        // SwiftUI : ce dernier s'ouvre dans sa propre NSWindow systeme, hors du
        // GlassEffectContainer de la coquille (§ NotchGlassSurface), et rendait
        // donc son propre materiau plat au lieu du Liquid Glass attendu — quel
        // que soit le style pose sur son contenu. Un overlay reste dans la
        // MEME hierarchie de vues que la coquille et herite du meme rendu.
        //
        // Alignement topLeading + offset manuel plutot qu'un alignement relatif
        // au bouton : un overlay ne redimensionne jamais son parent, donc il
        // peut deborder de la fenetre hote (260 pt de haut, § NotchWindowController)
        // sans etre tronque — contrairement a un element pousse dans le layout.
        .overlay(alignment: .topLeading) {
            if showsMoreMenu {
                ZStack(alignment: .topLeading) {
                    // Calque invisible plein cadre : `.popover` fermait tout
                    // seul au clic exterieur, un overlay maison doit le faire
                    // a la main. Sous le menu dans le ZStack, donc jamais
                    // prioritaire sur ses propres boutons.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(Theme.Motion.morph) { showsMoreMenu = false }
                        }

                    moreMenuContent
                        .offset(x: 32, y: 32)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }
        }
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

    /// Bouton rond, identique a `GlassIconButton`, qui bascule l'overlay
    /// `moreMenuContent` (§ body, voir `showsMoreMenu`).
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
    }

    /// Regroupe tous les onglets sauf Accueil en une seule rangee d'icones —
    /// meme gabarit que `GlassIconButton`, meme largeur que la barre d'onglets
    /// d'origine avait avant sa reduction. Une liste verticale de labels
    /// (essais precedents) imposait sa largeur au texte le plus long
    /// ("Statistiques système") et donnait un popover etroit mais haut ; une
    /// rangee horizontale reste fine et se cale naturellement sur le panneau.
    /// Habille avec `GlassCard` — la seule combinaison de materiau deja
    /// confirmee correcte partout ailleurs dans l'app.
    private var moreMenuContent: some View {
        GlassCard(cornerRadius: 14) {
            HStack(spacing: 6) {
                ForEach(NotchTab.allCases.filter { $0 != .home }) { tab in
                    Button {
                        showsMoreMenu = false
                        select(tab)
                    } label: {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.selectedTab == tab ? Theme.Palette.ember : Theme.Palette.frost)
                    .accessibilityLabel(tab.accessibilityLabel)
                }
            }
            .padding(8)
        }
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
                openTimerTab: { select(.timer) },
                openStatsTab: { select(.stats) }
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
            QuickSettingsTabView(widgets: widgets)
        }
    }
}
