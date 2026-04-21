import Foundation
import Observation

@Observable
class DataManager {
    private let fileManager = FileManager.default

    private var appSupportDir: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeskRun", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var goalsURL: URL { appSupportDir.appendingPathComponent("goals.json") }
    private var workoutsURL: URL { appSupportDir.appendingPathComponent("workouts.json") }
    private var settingsURL: URL { appSupportDir.appendingPathComponent("settings.json") }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Goals

    func loadGoals() -> [Goal] {
        load(from: goalsURL) ?? []
    }

    func saveGoals(_ goals: [Goal]) {
        save(goals, to: goalsURL)
    }

    // MARK: - Workouts

    func loadWorkouts() -> [WorkoutRecord] {
        load(from: workoutsURL) ?? []
    }

    func saveWorkouts(_ workouts: [WorkoutRecord]) {
        save(workouts, to: workoutsURL)
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        load(from: settingsURL) ?? AppSettings()
    }

    func saveSettings(_ settings: AppSettings) {
        save(settings, to: settingsURL)
    }

    // MARK: - Generic

    private func load<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
