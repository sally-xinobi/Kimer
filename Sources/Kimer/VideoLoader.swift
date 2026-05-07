import Foundation

/// A single character's idle/run video pair.
struct CharacterAssets: Identifiable, Equatable {
    let id: String              // e.g. "cat", "mouse"
    let displayName: String     // e.g. "Cat", "Mouse"
    let idleURL: URL
    let runURL: URL
}

/// Scans the bundle's Resources for paired `<name>_idle.*` / `<name>_run.*`
/// videos and produces a sorted library of selectable characters. Adding a new
/// character is just a matter of dropping two more files into Resources.
enum VideoLoader {

    private static let extensions: Set<String> = ["mov", "mp4", "m4v"]

    static func loadLibrary() -> [CharacterAssets] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil
        )) ?? []

        var pairs: [String: (idle: URL?, run: URL?)] = [:]
        for url in files {
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            if stem.hasSuffix("_idle") {
                let key = String(stem.dropLast("_idle".count))
                pairs[key, default: (nil, nil)].idle = url
            } else if stem.hasSuffix("_run") {
                let key = String(stem.dropLast("_run".count))
                pairs[key, default: (nil, nil)].run = url
            }
        }

        return pairs.compactMap { key, urls -> CharacterAssets? in
            guard let idle = urls.idle, let run = urls.run else { return nil }
            return CharacterAssets(
                id: key,
                displayName: key.prefix(1).uppercased() + key.dropFirst(),
                idleURL: idle,
                runURL: run
            )
        }
        .sorted { $0.id < $1.id }
    }
}
