import Foundation

/// Where one running install is, in words and (only when it can be measured)
/// numbers. Built from the lines a source reports: PrismPack's own markers
/// (`§step:`, `§download:<done>/<total>`) and the tools' own output.
///
/// A percentage exists only where something real was measured: a download's
/// bytes, or a percentage the tool itself printed. Everywhere else `fraction`
/// is nil and the tile shows a spinner and says progress can't be measured
/// (Nick, 2 Nov 2026).
struct InstallProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case starting, prepare, download, verify, unpack, install, vendor, move, cleanup, finish, password

        var title: String {
            switch self {
            case .starting: "Starting"
            case .prepare: "Preparing"
            case .download: "Downloading"
            case .verify: "Verifying"
            case .unpack: "Unzipping"
            case .install: "Installing"
            case .vendor: "Running the vendor's installer"
            case .move: "Moving to Applications"
            case .cleanup: "Cleaning up"
            case .finish: "Finishing"
            case .password: "Needs your password"
            }
        }
    }

    private(set) var phase: Phase = .starting
    private(set) var downloaded: Int64 = 0
    private(set) var total: Int64?
    /// A percentage the tool printed itself (a download, or the macOS installer).
    private(set) var percent: Int?
    var startedAt = Date()

    /// 0...1, or nil when nothing real is known.
    var fraction: Double? {
        if phase == .download, let total, total > 0 { return min(1, Double(downloaded) / Double(total)) }
        return percent.map { Double(min($0, 100)) / 100 }
    }

    var percentText: Int? { fraction.map { Int(($0 * 100).rounded()) } }

    /// "412 MB of 1.2 GB", while downloading.
    var bytesText: String? {
        guard phase == .download, downloaded > 0 else { return nil }
        let done = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
        return total.map { "\(done) of \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))" } ?? done
    }

    /// The one line under the bar.
    func line(now: Date) -> String {
        if let bytes = bytesText { return "Downloading · \(bytes)" }
        var text = fraction == nil ? "\(phase.title)…" : phase.title
        let seconds = Int(now.timeIntervalSince(startedAt))
        if fraction == nil, seconds >= 60 { text += " \(Self.clock(seconds))" }
        return text
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private mutating func set(_ new: Phase) {
        guard new != phase else { return }
        phase = new
        percent = nil
    }

    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d{1,3})(?:\.\d+)?\s*%"#)
    private static let installerPercent = try! NSRegularExpression(pattern: #"percent complete:\s*(\d{1,3})"#, options: .caseInsensitive)

    private static func firstNumber(_ regex: NSRegularExpression, in line: String) -> Int? {
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).last
            .flatMap { Int(ns.substring(with: $0.range(at: 1))) }
    }

    /// Folds in one reported line.
    mutating func take(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("§download:") {
            let parts = line.dropFirst(10).split(separator: "/")
            downloaded = Int64(parts.first ?? "") ?? downloaded
            if parts.count > 1, let t = Int64(parts[1]), t > 0 { total = t }
            if phase == .starting || phase == .prepare { phase = .download }
            // Homebrew checks the file's checksum once it's all there.
            if phase == .download, let total, downloaded >= total { set(.verify) }
            return
        }
        if line.hasPrefix("§step:") {
            switch line.dropFirst(6) {
            case "prepare": set(.prepare)
            case "download": set(.download)
            case "check": set(.verify)
            case "trash": set(.cleanup)
            case "swap", "install": set(.install)
            case "launch": set(.finish)
            default: break
            }
            return
        }
        guard !line.hasPrefix("§"), !line.isEmpty else { return }
        let l = line.lowercased()
        if l.contains("password") { set(.password); return }
        if let p = Self.firstNumber(Self.installerPercent, in: line) { set(.vendor); percent = min(p, 100); return }

        if l.hasPrefix("==> downloading") || l.hasPrefix("==> fetching") || l.hasPrefix("downloading") || l.hasPrefix("collecting") {
            set(.download)
            // A percentage in a download line counts only without byte counts.
            if total == nil, let p = Self.firstNumber(Self.percentRegex, in: line) { percent = min(p, 100) }
        } else if l.contains("verifying") || l.contains("checksum") || l.contains("checking code signature") {
            set(.verify)
        } else if l.contains("unzip") || l.contains("unpacking") || l.contains("extracting") {
            set(.unpack)
        } else if l.contains("running installer") || l.hasPrefix("installer:") || l.contains("installing package") {
            set(.vendor)
        } else if l.contains("moving app") || l.contains("moving to /applications") || l.hasPrefix("==> linking") {
            set(.move)
        } else if l.contains("purging") || l.contains("cleaning up") || l.hasPrefix("==> removing") || l.contains("uninstalling") {
            set(.cleanup)
        } else if l.contains("successfully installed") || l.contains("relaunching") || l.contains("checking that") {
            set(.finish)
        } else if l.hasPrefix("==> installing") || l.hasPrefix("==> reinstalling") || l.hasPrefix("==> upgrading") || l.contains("pouring") || l.hasPrefix("installing")
                    || l.contains("compiling") || l.hasPrefix("building") {
            set(.install)
        } else if l.hasPrefix("downloading…") {
            set(.download)
        }
        // Sparkle: "Downloading… 12 MB / 50 MB (24%)".
        if phase == .download, total == nil, l.hasPrefix("downloading…"), let p = Self.firstNumber(Self.percentRegex, in: line) {
            percent = min(p, 100)
        }
    }
}
