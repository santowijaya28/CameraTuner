import Foundation

struct CameraProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var software: SoftwareSettings
    var hardware: [String: Int]
    var updatedAt = Date()
}

struct ProfileStore {
    private struct Payload: Codable {
        var profiles: [String: [CameraProfile]] = [:]
        var defaults: [String: String] = [:]
    }

    private let storageKey = "CameraTuner.profiles.v1"
    private let userDefaults: UserDefaults
    private var payload: Payload

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        } else {
            payload = Payload()
        }
    }

    func profiles(for cameraKey: String) -> [CameraProfile] {
        payload.profiles[cameraKey] ?? []
    }

    func defaultName(for cameraKey: String) -> String? {
        guard let name = payload.defaults[cameraKey],
              profiles(for: cameraKey).contains(where: {
                  $0.name.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            return nil
        }
        return name
    }

    mutating func saveProfile(
        named name: String,
        software: SoftwareSettings,
        hardware: [String: Int],
        for cameraKey: String
    ) -> CameraProfile {
        var list = payload.profiles[cameraKey] ?? []
        let now = Date()

        if let index = list.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            list[index].name = name
            list[index].software = software
            list[index].hardware = hardware
            list[index].updatedAt = now
            payload.profiles[cameraKey] = list
            if payload.defaults[cameraKey]?.caseInsensitiveCompare(name) == .orderedSame {
                payload.defaults[cameraKey] = name
            }
            persist()
            return list[index]
        }

        let profile = CameraProfile(
            name: name,
            software: software,
            hardware: hardware,
            updatedAt: now
        )
        list.append(profile)
        payload.profiles[cameraKey] = list
        persist()
        return profile
    }

    mutating func deleteProfile(named name: String, for cameraKey: String) {
        guard var list = payload.profiles[cameraKey] else { return }
        list.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        payload.profiles[cameraKey] = list

        if payload.defaults[cameraKey]?.caseInsensitiveCompare(name) == .orderedSame {
            payload.defaults[cameraKey] = nil
        }
        persist()
    }

    mutating func setDefaultProfile(named name: String?, for cameraKey: String) {
        payload.defaults[cameraKey] = name
        persist()
    }

    private mutating func persist() {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
