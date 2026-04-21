import Foundation

enum StepsEstimate {
    static let stepsPerMile = 2000
    private static let kmPerMile = 1.60934

    static func steps(fromKm km: Double) -> Int {
        guard km > 0 else { return 0 }
        return Int((km / kmPerMile * Double(stepsPerMile)).rounded())
    }
}
