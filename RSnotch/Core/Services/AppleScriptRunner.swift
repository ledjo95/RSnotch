import Foundation
import OSLog

private let scriptLog = Logger(subsystem: "com.varicube.RSnotch", category: "applescript")

// MARK: - AppleScriptError
enum AppleScriptError: Error, Equatable, Sendable {
    /// -1743 : l'utilisateur n'a pas accorde l'automatisation, ou l'a revoquee
    /// dans Reglages Systeme > Confidentialite et securite > Automatisation.
    case notAuthorized
    /// -600 / -609 : l'application ciblee n'est pas lancee. Ne devrait pas
    /// arriver — l'appelant verifie via NSWorkspace — mais une app peut quitter
    /// entre la verification et l'envoi.
    case targetNotRunning
    /// -1712 : la limite `with timeout` du script a expire. Le lecteur est
    /// lance mais ne repond pas.
    case timedOut
    case compilationFailed
    case executionFailed(code: Int, message: String)

    init(osaError: NSDictionary?) {
        let code = (osaError?[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (osaError?[NSAppleScript.errorMessage] as? String) ?? "Erreur AppleScript."
        switch code {
        case -1743, -1744: self = .notAuthorized
        case -600, -609, -1728: self = .targetNotRunning
        case -1712: self = .timedOut
        default: self = .executionFailed(code: code, message: message)
        }
    }
}

// MARK: - AppleScriptRunner
//
// NSAppleScript n'est pas thread-safe et son execution est BLOQUANTE : un aller
// -retour Apple Events vers Music.app prend couramment plusieurs dizaines de
// millisecondes. Le lancer sur le thread principal ferait saccader le morph du
// panneau a chaque releve.
//
// D'ou cette file serie dediee, avec un cache de scripts compiles : la
// compilation coute bien plus cher que l'execution, et les memes quatre ou cinq
// scripts tournent en boucle pendant toute la vie de l'app.
//
// LE CACHE EST INDEXE SUR LA SOURCE EXACTE. Un appelant qui construit sa source
// en y interpolant une valeur qui change a chaque appel (une position de
// lecture, par exemple) ne doit PAS laisser cette source passer par le cache :
// chaque valeur distincte y creerait une entree neuve, jamais reutilisee et
// jamais purgee — un cache qui grandit sans fin pour un gain nul. D'ou le
// parametre `cacheable`, que l'appelant doit mettre a `false` pour toute source
// dont un fragment varie d'un appel a l'autre.
//
// `@unchecked Sendable` : l'etat mutable (le cache) n'est touche que depuis
// `queue`, jamais concurremment.

final class AppleScriptRunner: @unchecked Sendable {

    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "com.varicube.RSnotch.applescript", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    private init() {}

    /// Execute une source et rend le descripteur brut. Les appelants typent le
    /// resultat eux-memes (texte pour les releves, donnees pour la pochette).
    ///
    /// `cacheable` a `false` pour une source qui embarque une valeur variable
    /// (voir la note en tete de fichier) : le script est alors compile et
    /// execute sans jamais entrer dans le cache.
    func run(_ source: String, cacheable: Bool = true) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try execute(source, cacheable: cacheable))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Variante sans valeur de retour, pour les commandes (play/pause, seek).
    func perform(_ source: String, cacheable: Bool = true) async throws {
        _ = try await run(source, cacheable: cacheable)
    }

    // MARK: File serie

    private func execute(_ source: String, cacheable: Bool) throws -> NSAppleEventDescriptor {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else {
                throw AppleScriptError.compilationFailed
            }
            var compileError: NSDictionary?
            guard compiled.compileAndReturnError(&compileError) else {
                scriptLog.error("compilation refusée : \(String(describing: compileError), privacy: .public)")
                throw AppleScriptError.compilationFailed
            }
            if cacheable { cache[source] = compiled }
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let mapped = AppleScriptError(osaError: error)
            // L'absence d'autorisation est un etat de l'app, pas un incident :
            // la journaliser en erreur noierait les vraies pannes.
            if mapped == .notAuthorized || mapped == .timedOut {
                scriptLog.debug("écarté : \(String(describing: mapped), privacy: .public)")
            } else {
                scriptLog.error("exécution échouée : \(String(describing: error), privacy: .public)")
            }
            throw mapped
        }
        return result
    }
}
