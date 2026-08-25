import CoreGraphics
import Foundation
import OSLog

private let brightnessLog = Logger(subsystem: "com.varicube.RSnotch", category: "brightness")

// MARK: - BrightnessControl
//
// Lecture ET ecriture de la luminosite de l'ecran interne.
//
// ATTENTION — SYMBOLES PRIVES, ISOLES ICI ET NULLE PART AILLEURS.
//
// POURQUOI. Aucune API publique ne lit ni n'ecrit la luminosite de l'ecran
// interne sur Apple Silicon. `IODisplaySetFloatParameter` / `GetFloatParameter`
// sont publiques mais travaillent sur des services `IODisplayConnect`, dont ces
// machines n'exposent AUCUN — verifie : zero service enumere. Il ne reste que
// `DisplayServices`, framework prive.
//
// Ce compromis n'aurait pas ete acceptable tant que RSnotch visait le Mac App
// Store : les API privees y sont interdites. La distribution est passee en
// Developer ID le 25 aout 2026 precisement pour pouvoir masquer le HUD systeme,
// et la revue App Store ne s'applique plus. Le second risque, lui, demeure :
// Apple peut retirer ces symboles a n'importe quelle mise a jour.
//
// D'OU CES TROIS PRECAUTIONS :
//   1. RESOLUTION A L'EXECUTION (`dlopen` / `dlsym`), jamais un lien a
//      l'edition de liens. Si le framework ou le symbole disparait, l'app
//      demarre quand meme — elle perd la fonction, pas son lancement.
//   2. `isAvailable` expose l'echec. L'appelant NE DOIT PAS avaler la touche
//      de luminosite quand il vaut `false` : mieux vaut le HUD de macOS que des
//      touches mortes.
//   3. Tout le code prive tient dans ce fichier. Le reste de l'app ne connait
//      que `brightness` et `setBrightness(_:)`.

enum BrightnessControl {

    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID, UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols {
        let get: GetBrightness
        let set: SetBrightness
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            brightnessLog.notice("DisplayServices introuvable : contrôle de luminosité désactivé")
            return nil
        }
        guard let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            brightnessLog.notice("symboles de luminosité absents : contrôle désactivé")
            return nil
        }
        return Symbols(
            get: unsafeBitCast(getSymbol, to: GetBrightness.self),
            set: unsafeBitCast(setSymbol, to: SetBrightness.self)
        )
    }()

    /// `false` quand les symboles n'ont pas pu etre resolus. L'appelant doit
    /// alors laisser passer les touches de luminosite au systeme.
    static var isAvailable: Bool { symbols != nil }

    /// Luminosite courante, 0…1. Valeur EXACTE — celle du curseur des Reglages
    /// Systeme, pas une reconstitution.
    static func brightness(of display: CGDirectDisplayID = CGMainDisplayID()) -> Double? {
        guard let symbols else { return nil }
        var value: Float = 0
        guard symbols.get(display, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }

    @discardableResult
    static func setBrightness(
        _ value: Double, on display: CGDirectDisplayID = CGMainDisplayID()
    ) -> Bool {
        guard let symbols else { return false }
        let clamped = Float(min(max(value, 0), 1))
        return symbols.set(display, clamped) == 0
    }
}
