import Foundation
import PolyplotCore

/// The content catalog (docs/06-content-catalog.md): a list bundled with the app, one per language
/// (`LanguagePack.catalog`). New suggestions arrive with app updates; nothing is downloaded.
enum ContentLibrary {
    static func load(_ pack: LanguagePack) -> ContentCatalog {
        guard let url = Bundle.main.url(forResource: pack.catalog.resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? ContentCatalog.decode(data)
        else { return ContentCatalog(version: 0, items: []) }
        return catalog
    }
}
