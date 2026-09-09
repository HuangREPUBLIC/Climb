import Foundation
import SwiftData

@Model
final class TFTStats {
    var placement: Int
    var level: Int
    var traits: [String]
    var units: [String]

    var match: Match?

    init(placement: Int, level: Int, traits: [String], units: [String]) {
        self.placement = placement
        self.level = level
        self.traits = traits
        self.units = units
    }
}
