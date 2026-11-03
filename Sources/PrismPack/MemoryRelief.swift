import Foundation
import Darwin

/// Hands memory the app has already freed back to the system. malloc keeps
/// such pages for reuse; decoding Homebrew's lists, `brew info` output and
/// icons left about 90 MB of them behind in a closed window.
enum MemoryRelief {
    /// Runs off the main thread, since it walks every malloc zone.
    static func run(after delay: TimeInterval = 0) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
}
