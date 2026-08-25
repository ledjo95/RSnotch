import Foundation
import SwiftData

// MARK: - ClipboardStore
//
// Conteneur SwiftData de l'historique du presse-papiers.
//
// Pourquoi SwiftData ici, alors que la disposition des widgets et la grappe
// d'applications tiennent dans UserDefaults : l'historique atteint des
// centaines d'entrees, porte des donnees binaires, et l'UI le filtre par type
// et par favori. C'est exactement ce qu'un magasin d'objets fait mieux qu'un
// blob JSON relu en entier a chaque ecriture.
//
// Le fichier vit dans le conteneur sandbox de l'app. Aucune option CloudKit :
// un historique de presse-papiers ne doit pas quitter la machine.

@MainActor
enum ClipboardStore {

    static let container: ModelContainer = {
        // La reprise de l'ancien conteneur doit avoir eu lieu AVANT qu'une base
        // ne soit ouverte ici, sinon SwiftData en cree une vide et la migration
        // la trouve deja en place — elle passe alors son chemin, et l'historique
        // reste orphelin dans le conteneur du bac a sable.
        //
        // L'appel est place ICI, et pas seulement dans `applicationDidFinishLaunching`,
        // parce que ce `static let` est evalue des l'initialisation de
        // `NotchWindowController`, qui est elle-meme une propriete stockee de
        // l'AppDelegate — donc AVANT que la methode de lancement ne s'execute.
        // La garantie appartient a la dependance, pas a l'ordre d'appel.
        // L'operation est idempotente : elle ne coute rien aux appels suivants.
        AppContainer.migrateFromSandboxContainer()

        let schema = Schema([ClipboardEntry.self])
        // Emplacement EXPLICITE. Par defaut SwiftData ecrit un `default.store`
        // dans `applicationSupportDirectory` — soit, hors bac a sable, la
        // racine du dossier partage de l'utilisateur, sous un nom que n'importe
        // quelle autre app peut revendiquer.
        let configuration: ModelConfiguration
        if let url = AppContainer.supportDirectory?
            .appending(path: "default.store", directoryHint: .notDirectory) {
            configuration = ModelConfiguration(
                schema: schema, url: url, cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Base illisible (schema incompatible, disque plein). Plutot que de
            // faire tomber l'app au lancement, on repart sur un magasin en
            // memoire : l'historique de la session est perdu, le reste du
            // panneau continue de fonctionner.
            //
            // Ce repli n'a plus aucune dependance disque : il ne peut donc
            // echouer que si SwiftData lui-meme est dans un etat rompu — pas
            // un cas que l'app puisse degrader proprement plus loin, faute
            // d'un `ModelContext` valide a offrir a quoi que ce soit.
            // `fatalError` documente ce cas plutot que de le masquer derriere
            // un `try!` muet : le message qui suit se lit dans le rapport de
            // crash, la ou le premier echec, lui, ne se voit que dans les logs.
            do {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError(
                    "SwiftData ne peut construire aucun ModelContainer, même en mémoire : \(error)"
                )
            }
        }
    }()
}
