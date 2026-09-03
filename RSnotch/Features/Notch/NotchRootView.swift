import SwiftUI

// MARK: - NotchRootView
//
// Racine SwiftUI hebergee dans le NSPanel. La fenetre couvre en permanence
// toute la bande superieure de l'ecran ; c'est cette vue qui decide de la
// taille reellement occupee et la publie au modele pour le hit-testing.
//
// Le changement d'etat n'anime PAS le frame de la fenetre : seule la forme de
// verre grandit, ce qui laisse GlassEffectContainer faire un vrai morph de
// materiau plutot qu'un redimensionnement saccade.

struct NotchRootView: View {

    @Bindable var model: NotchViewModel
    @Bindable var widgets: WidgetsViewModel
    @Bindable var launcher: LaunchItemsViewModel
    @Bindable var countdown: TimerService
    @Bindable var nowPlaying: NowPlayingViewModel
    var spaces: SpaceHeuristicService
    @Bindable var pocket: PocketStorageService
    let weather: WeatherService
    let calendar: CalendarService
    var settings: AppSettings = .shared
    @Namespace private var glassNamespace
    /// Hauteur de la fenetre hote, relevee une fois au layout.
    @State private var hostHeight: CGFloat = 0

    // MARK: Gabarits

    private var currentSize: CGSize {
        let notch = model.geometry.notchSize
        switch model.state {
        case .collapsed:
            return notch
        case .island(let payload):
            // Largeur mesuree sur le texte, bornee par l'ecran : un titre long
            // ne doit ni etre tronque, ni deborder de la dalle.
            let content = IslandMetrics.contentWidth(for: payload)
            let maximum = model.geometry.screenFrame.width * Theme.Metrics.maxScreenFraction
            return CGSize(
                width: min(notch.width + content, maximum),
                height: max(notch.height, 34)
            )
        case .expanded:
            // Largeur calee sur le contenu de l'onglet actif, bornee par la
            // largeur minimale de la barre d'onglets et par l'ecran.
            let scale = settings.panelWidth.scale
            // L'onglet Widgets se cale sur ses cartes ; les autres suivent le
            // gabarit de leur onglet, mis a l'echelle du reglage de largeur.
            let content = model.selectedTab == .home
                // Le reglage Compact/Standard/Large n'agissait PAS sur la page
                // principale : sa largeur se calait sur les cartes, dont la
                // taille ignorait l'echelle. Le reglage semblait donc sans effet
                // sur l'onglet le plus consulte.
                ? widgets.rowWidth(
                    spacing: Theme.Metrics.contentSpacing,
                    appItemCount: launcher.items.count,
                    scale: rowScale
                  )
                : Theme.Metrics.contentWidth(for: model.selectedTab, scale: scale)
            let screenWidth = model.geometry.screenFrame.width
            let width = min(
                max(
                    content + Theme.Metrics.panelHorizontalPadding * 2,
                    Theme.Metrics.minimumPanelWidth * scale
                ),
                Theme.Metrics.expandedMaxWidth,
                screenWidth * Theme.Metrics.maxScreenFraction
            )
            let height = Theme.Metrics.panelPadding * 2
                + 26                                   // barre d'onglets
                + Theme.Metrics.contentSpacing
                + Theme.Metrics.contentHeight(for: model.selectedTab)
            return CGSize(width: width, height: height)
        }
    }

    /// Echelle de la rangee de widgets, rabaissee si elle ne tenait pas dans le
    /// panneau. Calculee ici ET dans le panneau etendu, a partir des memes
    /// entrees : la largeur mesuree et la largeur dessinee doivent coincider,
    /// sinon la derniere carte est tronquee.
    private var rowScale: CGFloat {
        widgets.rowScale(
            requested: settings.panelWidth.scale,
            spacing: Theme.Metrics.contentSpacing,
            appItemCount: launcher.items.count,
            screenWidth: model.geometry.screenFrame.width
        )
    }

    /// Rayon inferieur de la coquille, concentrique avec le contenu qu'elle porte.
    private var shellRadius: CGFloat {
        switch model.state {
        case .collapsed: Theme.Metrics.notchCornerRadius
        case .island: Theme.Metrics.notchCornerRadius + 4
        case .expanded: NotchShape.concentric(
            inner: Theme.Metrics.cardCornerRadius,
            padding: Theme.Metrics.panelPadding
        )
        }
    }

    private var shellShape: NotchShape {
        NotchShape(bottomRadius: shellRadius)
    }

    private var filamentIntensity: Double {
        switch model.state {
        case .collapsed: 0
        case .island: 0.5
        case .expanded: 1
        }
    }

    // MARK: Corps

    var body: some View {
        // Pas de GlassEffectContainer ici : il est porte par NotchGlassSurface,
        // au plus pres des seules formes qui doivent fusionner.
        shell
        // La coquille est plaquee en haut, centree sur l'encoche.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            hostHeight = size.height
            publishActiveRect()
        }
        .onChange(of: currentSize) { _, _ in publishActiveRect() }
        .ignoresSafeArea()
        .environment(\.glassIntensity, settings.glassIntensity)
        // Teinte du bureau actif (§3.10). Elle traverse tout le panneau par
        // l'environnement : la coquille de verre et le filament la lisent deja.
        .environment(\.spaceAccent, spaceAccent)
        .environment(\.notchDragActivity) { model.dragActivity() }
        .environment(\.notchOpenLock) { locked in
            locked ? model.retainOpen() : model.releaseOpen()
        }
        // La fenetre du notch est volontairement non activable : AppKit la
        // considere donc comme inactive et grise tous les controles, ce qui
        // effacait l'etat selectionne des onglets. On force l'etat actif —
        // le panneau est toujours « au premier plan » du point de vue de
        // l'utilisateur, meme s'il ne prend jamais le focus.
        .environment(\.controlActiveState, .active)
        // Historique du presse-papiers : magasin SwiftData local au conteneur
        // sandbox, sans synchronisation.
        .modelContainer(ClipboardStore.container)
    }

    private var shell: some View {
        NotchGlassSurface(
            shape: shellShape,
            filamentIntensity: filamentIntensity,
            glassNamespace: glassNamespace
        ) {
            content
                .frame(width: currentSize.width, height: currentSize.height)
        }
        .contentShape(shellShape)
        .onContinuousHover { phase in
            switch phase {
            case .active: model.pointerEntered()
            case .ended: model.pointerExited()
            }
        }
        .onTapGesture { model.toggle() }
        // Detection du glisser LIMITEE a la bande de l'encoche.
        //
        // Appliquee a toute la coquille, elle couvrait le panneau deplie en
        // entier et captait les depots destines aux zones AirDrop / Pocket :
        // l'action de la coquille l'emportait sur celle de ses enfants, et le
        // fichier disparaissait sans etre traite.
        //
        // Reduite a l'encoche, elle ne fait plus que deux choses : deplier le
        // panneau quand un fichier s'attarde, et servir de raccourci — lacher
        // directement sur l'encoche range dans la Pocket.
        // En ARRIERE-PLAN, pas en superposition : posee devant, cette zone
        // couvrirait la barre d'onglets et en bloquerait les clics. Derriere,
        // elle ne recoit un depot que si aucun enfant ne s'en saisit.
        .background(alignment: .top) { notchDropCatcher }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panneau RSnotch")
    }

    // MARK: Contenus par etat

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .collapsed:
            // Au repos la forme reste vide : elle doit disparaitre dans l'encoche.
            Color.clear
        case .island(let payload):
            Group {
                if let level = payload.level {
                    LevelIslandView(
                        payload: payload,
                        level: level,
                        notchWidth: model.geometry.notchSize.width
                    )
                } else {
                    CompactIslandView(
                        payload: payload,
                        notchWidth: model.geometry.notchSize.width
                    )
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        case .expanded:
            ExpandedPanelView(
                model: model,
                widgets: widgets,
                launcher: launcher,
                countdown: countdown,
                nowPlaying: nowPlaying,
                pocket: pocket,
                weather: weather,
                calendar: calendar,
                settings: settings,
                glassNamespace: glassNamespace
            )
                .transition(.opacity)
        }
    }

    /// Cible de depot de la taille de l'encoche, posee au sommet de la coquille.
    private var notchDropCatcher: some View {
        Color.clear
            .frame(
                width: model.geometry.notchSize.width,
                height: model.geometry.notchSize.height
            )
            .fileDropDestination(
                mode: .materialized,
                isTargeted: Binding(
                    get: { model.isReceivingDrag },
                    set: { $0 ? model.dragEntered() : model.dragExited() }
                )
            ) { urls in
                model.holdOpen()
                guard pocket.add(urls, movingSource: true) > 0 else { return }
                model.restoreTabAfterDrag(to: .pocket)
            }
    }

    /// Teinte courante, ou `nil` si le reglage est desactive ou si
    /// l'heuristique n'a rien de fiable a dire.
    private var spaceAccent: Color? {
        guard settings.spaceTintEnabled, spaces.isAvailable else { return nil }
        return SpaceAccent.color(for: spaces.currentIndex)
    }

    // MARK: Hit-testing

    /// Convertit le gabarit courant en rect fenetre (origine bas-gauche AppKit)
    /// et le transmet au modele.
    private func publishActiveRect() {
        guard hostHeight > 0 else { return }
        let size = currentSize
        // La coquille est centree horizontalement dans la fenetre, qui couvre
        // toute la largeur de l'ecran : le centre vaut donc la demi-largeur.
        let centerX = model.geometry.screenFrame.width / 2
        model.activeRectInWindow = CGRect(
            x: centerX - size.width / 2,
            y: hostHeight - size.height,
            width: size.width,
            height: size.height
        )
    }
}
