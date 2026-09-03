import Foundation

// MARK: - SettingsExportService
//
// Construit et applique un `SettingsExportPayload`, et le lit/ecrit sur
// disque. Pas de dependance a `UserDefaults` directement : passe toujours
// par `AppSettings`/`WidgetsViewModel`, pour que le round-trip suive
// exactement leurs regles de validation existantes (bornes, replis par
// defaut) plutot que d'ecrire dans le magasin en le court-circuitant.

@MainActor
enum SettingsExportService {

    static func buildPayload(
        settings: AppSettings = .shared,
        widgets: WidgetsViewModel
    ) -> SettingsExportPayload {
        SettingsExportPayload(
            glassIntensity: settings.glassIntensity.rawValue,
            spaceTintEnabled: settings.spaceTintEnabled,
            clipboardLimit: settings.clipboardLimit,
            emptyPocketOnLaunch: settings.emptyPocketOnLaunch,
            panelEnabled: settings.panelEnabled,
            openOnHover: settings.openOnHover,
            hoverDelayMilliseconds: settings.hoverDelayMilliseconds,
            screenPreference: settings.screenPreference.rawValue,
            showWithoutNotch: settings.showWithoutNotch,
            simulatedBarWidth: settings.simulatedBarWidth,
            expandOnLaunch: settings.expandOnLaunch,
            volumeHUDEnabled: settings.volumeHUDEnabled,
            brightnessHUDEnabled: settings.brightnessHUDEnabled,
            replaceSystemHUD: settings.replaceSystemHUD,
            showLauncherLabels: settings.showLauncherLabels,
            gaugeTint: settings.gaugeTint.rawValue,
            widgetsLayout: widgets.widgets,
            widgetProfiles: widgets.profiles
        )
    }

    static func apply(
        _ payload: SettingsExportPayload,
        settings: AppSettings = .shared,
        widgets: WidgetsViewModel
    ) {
        if let value = payload.glassIntensity.flatMap(GlassIntensity.init(rawValue:)) {
            settings.glassIntensity = value
        }
        if let value = payload.spaceTintEnabled { settings.spaceTintEnabled = value }
        if let value = payload.clipboardLimit { settings.clipboardLimit = value }
        if let value = payload.emptyPocketOnLaunch { settings.emptyPocketOnLaunch = value }
        if let value = payload.panelEnabled { settings.panelEnabled = value }
        if let value = payload.openOnHover { settings.openOnHover = value }
        if let value = payload.hoverDelayMilliseconds { settings.hoverDelayMilliseconds = value }
        if let value = payload.screenPreference.flatMap(ScreenPreference.init(rawValue:)) {
            settings.screenPreference = value
        }
        if let value = payload.showWithoutNotch { settings.showWithoutNotch = value }
        if let value = payload.simulatedBarWidth { settings.simulatedBarWidth = value }
        if let value = payload.expandOnLaunch { settings.expandOnLaunch = value }
        if let value = payload.volumeHUDEnabled { settings.volumeHUDEnabled = value }
        if let value = payload.brightnessHUDEnabled { settings.brightnessHUDEnabled = value }
        if let value = payload.replaceSystemHUD { settings.replaceSystemHUD = value }
        if let value = payload.showLauncherLabels { settings.showLauncherLabels = value }
        if let value = payload.gaugeTint.flatMap(GaugeTint.init(rawValue:)) {
            settings.gaugeTint = value
        }

        if let layout = payload.widgetsLayout {
            widgets.replaceLayout(layout.filter { $0.kind.isAvailable })
        }
        if let profiles = payload.widgetProfiles {
            widgets.replaceProfiles(profiles)
        }
    }

    // MARK: Fichier

    enum ExportError: Error {
        case invalidFile
    }

    static func write(_ payload: SettingsExportPayload, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> SettingsExportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(SettingsExportPayload.self, from: data)
        } catch {
            throw ExportError.invalidFile
        }
    }
}
