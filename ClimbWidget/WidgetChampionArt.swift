import Foundation

/// Minimal duplicate of DataDragonService.splashArtURL for the widget target
/// — splash URLs don't need a patch version, so no actor/caching needed here.
enum WidgetChampionArt {
    static func splashURL(for championName: String) -> URL? {
        let id = championName.filter { $0.isLetter || $0.isNumber }
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/img/champion/splash/\(id)_0.jpg")
    }
}
