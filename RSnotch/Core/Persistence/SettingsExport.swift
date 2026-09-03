import Foundation

// MARK: - SettingsExportPayload
//
// Reglages exportables vers un fichier, pour les reprendre sur un autre Mac.
// Champs `Optional` plutot qu'un blob opaque : un import d'un format plus
// ancien laisse les champs absents a leur valeur courante au lieu d'echouer.
//
// EXCLU DELIBEREMENT :
//   - `launcher.items` et `bookmark.launch.*` — bloc couple non portable
//     (§ AppContainer.coupledKeys). Exporter la liste sans les bookmarks
//     produirait des tuiles dont TOUS les lancements echoueraient sur la
//     machine cible — un etat degrade qu'il vaut mieux ne jamais creer.
//   - `panel.width` — fige a `.large` en dur dans `AppSettings.init`, sans
//     effet ; inutile de le faire voyager.
//   - marqueurs techniques (`container.migratedFromSandbox`,
//     `onboarding.hudPrimerShown`) — pas des reglages.

struct SettingsExportPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date

    var glassIntensity: String?
    var spaceTintEnabled: Bool?
    var clipboardLimit: Int?
    var emptyPocketOnLaunch: Bool?
    var panelEnabled: Bool?
    var openOnHover: Bool?
    var hoverDelayMilliseconds: Int?
    var screenPreference: String?
    var showWithoutNotch: Bool?
    var simulatedBarWidth: Double?
    var expandOnLaunch: Bool?
    var volumeHUDEnabled: Bool?
    var brightnessHUDEnabled: Bool?
    var replaceSystemHUD: Bool?
    var showLauncherLabels: Bool?
    var gaugeTint: String?

    var widgetsLayout: [PanelWidget]?
    var widgetProfiles: [WidgetLayoutProfile]?

    static let currentFormatVersion = 1

    init(
        formatVersion: Int = SettingsExportPayload.currentFormatVersion,
        exportedAt: Date = Date(),
        glassIntensity: String? = nil,
        spaceTintEnabled: Bool? = nil,
        clipboardLimit: Int? = nil,
        emptyPocketOnLaunch: Bool? = nil,
        panelEnabled: Bool? = nil,
        openOnHover: Bool? = nil,
        hoverDelayMilliseconds: Int? = nil,
        screenPreference: String? = nil,
        showWithoutNotch: Bool? = nil,
        simulatedBarWidth: Double? = nil,
        expandOnLaunch: Bool? = nil,
        volumeHUDEnabled: Bool? = nil,
        brightnessHUDEnabled: Bool? = nil,
        replaceSystemHUD: Bool? = nil,
        showLauncherLabels: Bool? = nil,
        gaugeTint: String? = nil,
        widgetsLayout: [PanelWidget]? = nil,
        widgetProfiles: [WidgetLayoutProfile]? = nil
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.glassIntensity = glassIntensity
        self.spaceTintEnabled = spaceTintEnabled
        self.clipboardLimit = clipboardLimit
        self.emptyPocketOnLaunch = emptyPocketOnLaunch
        self.panelEnabled = panelEnabled
        self.openOnHover = openOnHover
        self.hoverDelayMilliseconds = hoverDelayMilliseconds
        self.screenPreference = screenPreference
        self.showWithoutNotch = showWithoutNotch
        self.simulatedBarWidth = simulatedBarWidth
        self.expandOnLaunch = expandOnLaunch
        self.volumeHUDEnabled = volumeHUDEnabled
        self.brightnessHUDEnabled = brightnessHUDEnabled
        self.replaceSystemHUD = replaceSystemHUD
        self.showLauncherLabels = showLauncherLabels
        self.gaugeTint = gaugeTint
        self.widgetsLayout = widgetsLayout
        self.widgetProfiles = widgetProfiles
    }
}
