import Foundation
import OSLog

private let containerLog = Logger(subsystem: "com.varicube.RSnotch", category: "container")

// MARK: - AppContainer
//
// Ou vivent les donnees de RSnotch, et comment elles ont survecu au retrait du
// bac a sable.
//
// LE PROBLEME. En bac a sable, `applicationSupportDirectory` designait
// automatiquement un dossier PROPRE A L'APP, dans son conteneur :
//   ~/Library/Containers/com.varicube.RSnotch/Data/Library/Application Support/
// Hors bac a sable, la meme API rend le dossier PARTAGE de l'utilisateur :
//   ~/Library/Application Support/
// Le code n'ayant pas change, la Pocket, le sas de depot et surtout la base
// SwiftData `default.store` — au nom parfaitement generique — se seraient
// ecrits en vrac a la racine du dossier de l'utilisateur, au risque d'ecraser
// le fichier d'une autre app. D'ou `supportDirectory`, qui redonne
// explicitement le sous-dossier que le bac a sable offrait gratuitement.
//
// LE SECOND PROBLEME, PLUS GRAVE. Le retrait du bac a sable a rendu l'ancien
// conteneur INVISIBLE a l'app : preferences, applications epinglees, historique
// du presse-papiers et Pocket etaient toujours sur le disque, mais l'app
// demarrait sur une ardoise vierge. `migrateFromSandboxContainer()` rapatrie
// tout cela, une seule fois.
//
// La migration COPIE, elle ne deplace pas : l'ancien conteneur reste intact
// tant que l'utilisateur ne l'efface pas lui-meme. Une migration qui echoue a
// mi-chemin ne doit pas emporter les donnees d'origine avec elle.

enum AppContainer {

    private static let bundleID = "com.varicube.RSnotch"
    /// Marqueur de migration. Tant qu'il est absent, la migration est tentee.
    private static let migrationKey = "container.migratedFromSandbox"

    /// Instance locale a chaque appel plutot que partagee : `FileManager`
    /// n'est pas `Sendable`, et un singleton statique ne passerait pas le
    /// controle de concurrence de Swift 6.
    private static var fileManager: FileManager { FileManager.default }

    // MARK: Emplacements

    /// Dossier de donnees de l'app. Cree a la demande.
    static var supportDirectory: URL? {
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        let directory = support.appending(path: "RSnotch", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Sous-dossier nomme, cree a la demande.
    static func directory(named name: String) -> URL? {
        guard let root = supportDirectory else { return nil }
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Ancien conteneur du bac a sable, s'il existe encore.
    private static var sandboxContainer: URL? {
        let url = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(bundleID)/Data", directoryHint: .isDirectory)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Migration
    //
    // A APPELER AVANT TOUTE LECTURE DE DONNEES — donc avant que le conteneur
    // SwiftData ne soit instancie, faute de quoi la base vide serait creee la
    // premiere et la base migree arriverait trop tard.

    static func migrateFromSandboxContainer() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        guard let container = sandboxContainer else {
            // Rien a migrer : installation neuve. On pose quand meme le
            // marqueur, pour ne pas re-tester a chaque lancement.
            defaults.set(true, forKey: migrationKey)
            return
        }

        containerLog.notice("migration depuis l'ancien conteneur du bac à sable")
        migratePreferences(from: container)
        migrateFiles(from: container)
        defaults.set(true, forKey: migrationKey)
        containerLog.notice("migration terminée")
    }

    /// Cles qui ne veulent rien dire seules.
    ///
    /// `launcher.items` decrit les applications epinglees ; chaque element y
    /// renvoie a un `bookmark.launch.<uuid>` qui, lui, porte le chemin. Reprendre
    /// l'un sans l'autre donne une grappe de tuiles vides — ce qui EST arrive :
    /// une liste ecrite apres le retrait du bac a sable a survecu a la
    /// migration, pendant que les bookmarks repris pointaient vers d'autres
    /// identifiants. Ces cles se reprennent donc EN BLOC, ou pas du tout.
    private static let coupledKeys = "launcher.items"

    /// Reprend les preferences de l'ancien conteneur.
    ///
    /// Regle generale : ne remplace JAMAIS une cle deja presente — entre le
    /// retrait du bac a sable et cette migration, l'utilisateur a pu regler
    /// quelque chose dans la version neuve, et son choix le plus recent doit
    /// gagner. L'exception est le bloc couple ci-dessus.
    ///
    /// `defaults` injectable : point de testabilite, la valeur par defaut
    /// preserve le comportement de production sans toucher `migrateFromSandboxContainer()`.
    static func migratePreferences(from container: URL, defaults: UserDefaults = .standard) {
        let plist = container.appending(
            path: "Library/Preferences/\(bundleID).plist", directoryHint: .notDirectory
        )
        guard let stored = NSDictionary(contentsOf: plist) as? [String: Any] else { return }

        var restored = 0
        for (key, value) in stored where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            restored += 1
        }

        // Le bloc couple : si la liste d'applications est reprise, les
        // bookmarks qu'elle designe doivent l'etre aussi, et inversement. On
        // les traite ensemble, en ecrasant ce qui traine cote neuf.
        if defaults.object(forKey: coupledKeys) == nil || restored > 0,
           let list = stored[coupledKeys] {
            defaults.set(list, forKey: coupledKeys)
            for (key, value) in stored where key.hasPrefix("bookmark.launch.") {
                defaults.set(value, forKey: key)
            }
        }

        containerLog.notice("préférences reprises : \(restored) clé(s)")
    }

    /// Rapatrie la base du presse-papiers et les fichiers de la Pocket.
    private static func migrateFiles(from container: URL) {
        guard let destination = supportDirectory else { return }
        let source = container.appending(
            path: "Library/Application Support", directoryHint: .isDirectory
        )

        // `default.store` porte la base SwiftData ; ses fichiers `-wal` et
        // `-shm` portent les ecritures pas encore fusionnees. Les oublier
        // ramenerait une base amputee de ses dernieres entrees.
        let items = ["default.store", "default.store-wal", "default.store-shm", "Pocket"]
        for name in items {
            let from = source.appending(path: name)
            let to = destination.appending(path: name)
            guard fileManager.fileExists(atPath: from.path),
                  !fileManager.fileExists(atPath: to.path)
            else { continue }
            do {
                try fileManager.copyItem(at: from, to: to)
                containerLog.notice("repris : \(name, privacy: .public)")
            } catch {
                containerLog.error("échec de reprise \(name, privacy: .public) : \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
