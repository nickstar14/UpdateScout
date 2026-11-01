import SwiftUI

/// One-time pop-up for people upgrading from UpdateScout (rename plan,
/// section 7; Nick asked for a pop-up with a prism effect instead of a banner).
/// A white beam travels in from the edge and hits the old icon, which explodes
/// into a ball of white light; the ball clears to reveal the new icon, and the
/// prism splits the light into the icon's six colours, shining down behind the
/// name as it changes. The rays then breathe gently (Nick's sequence). Reduce
/// Motion shows the end state.
struct RenameWelcome: View {
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var beam = false
    @State private var hit = false
    @State private var ball = false
    @State private var ballGone = false
    @State private var morphed = false
    @State private var spread = false
    @State private var renamed = false
    @State private var settled = false
    @State private var breathe = false

    private static let legacyIcon: NSImage? = Bundle.main.image(forResource: "LegacyIcon")
    private static let iconSize: CGFloat = 92
    /// Where the icon's centre sits in the stage; the beam ends and the rays
    /// start here.
    private static let iconCentre: CGFloat = 58
    private static let rayLength: CGFloat = 200
    /// Long enough to start at the pop-up's left edge (the icon sits 250 pt in).
    private static let beamLength: CGFloat = 262
    private static let beamAngle: Double = 12

    var body: some View {
        VStack(spacing: 10) {
            // Top-aligned: the rays reach past the stage and must not move it.
            stage.frame(width: 440, height: 190, alignment: .top)
            VStack(spacing: 14) {
                // The story and the changelog scroll together, so the sheet
                // fits any window and Continue stays in view.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        story
                        changelog
                    }
                    .padding(14)
                }
                .frame(height: 270)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                Button(action: dismiss) {
                    Text("Continue").frame(minWidth: 120)
                }
                .prismProminent()
                .keyboardShortcut(.defaultAction)
            }
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 8)
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 20)
        .frame(width: 500)
        .task { await play() }
    }

    /// Why the name changed (Nick's reasons, in the app's words).
    private var story: some View {
        let name = AppIdentity.name
        return VStack(alignment: .leading, spacing: 10) {
            Text("UpdateScout is now \(name).").font(.headline)
            Text("Version 2.0 is much more than an updater. Alongside updates, \(name) now helps you find and install new apps, and look after everything you already have. The old name no longer covered all of that.")
            Text("Finding a name that fit, and that nobody else was using, took a while. We chose \(name) because a prism takes a single beam of white light and reveals every colour inside it. \(name) does the same for your Mac: one window that shows all your software, from Homebrew, the App Store and Sparkle apps to Python, npm, Rust and more, each in its own colour.")
            Text("Your settings and history carried over.").foregroundStyle(.primary)
        }
        .font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What's new in 2.0, checked against the 1.8.0 code (30 Oct 2026). Draft
    /// for Nick to approve before a beta. Only what's built: through Phase 9's
    /// leftover cleanup, Orphaned App Files and Full Disk Access (31 Oct 2026).
    static let changes: [(symbol: String, title: String, detail: String)] = [
        ("macwindow", "A new window", "A sidebar with Updates, Discover, Installed, Activity and Settings, in the macOS 27 Liquid Glass look."),
        ("triangle", "A new menu bar prism", "Click it to open the window. Right-click for Check Now, Settings and Quit. It replaces the old pop-up menu."),
        ("magnifyingglass", "Discover", "Find and install new apps and tools from Homebrew, npm, PyPI, crates.io, RubyGems and the editor extension stores. Browse what's popular this month, what's new, and apps by category."),
        ("square.stack.3d.up.fill", "More kinds of updates", "New sections for Python (pipx and uv), npm, Rust, Ruby gems, and extensions for VS Code, VSCodium and Cursor, plus a Tools section for the package managers themselves."),
        ("arrow.down.circle", "Several updates at once", "Updates run side by side, each with its own progress and Cancel, while each package manager still does one thing at a time. Choose how many in Settings."),
        ("key.fill", "One password per batch", "Enter it once for a whole batch. It's kept in memory for that batch only and never saved."),
        ("checkmark.circle", "Installed", "Everything on your Mac in one list, showing where each item came from and whether it's up to date."),
        ("trash", "Uninstall", "Remove an app or package from its card, the right way for wherever it came from. Before anything moves, one window shows the app, the files it left in your Library, and Homebrew's cleanup list. You choose what goes, and it goes to the Trash so you can put it back."),
        ("questionmark.folder", "Orphaned App Files", "Files left behind by apps you've already removed, with their size and when they last changed. Nothing is ticked: keep them or move what you choose to the Trash."),
        ("lock.shield", "Full Disk Access", "Optional. Lets \(AppIdentity.name) clear the app data folders macOS protects. Settings → Setup explains why and helps you turn it on, and it stays on through updates."),
        ("mug.fill", "Move apps under Homebrew", "\(AppIdentity.name) spots apps nothing keeps up to date that Homebrew could, checks that Homebrew is really better for each one, and moves it only when you click. You can undo it later."),
        ("square.on.square", "Duplicates", "Two copies of one app, or an App Store app Homebrew also tracks, are pointed out with a one-click fix. Nothing is removed without asking, and copies go to the Trash."),
        ("clock.arrow.circlepath", "Activity", "A history of checks, updates, installs and removals. Failures keep their log, and you can retry them."),
        ("arrow.triangle.branch", "Stable or Beta, per app", "Choose which release track each app follows, on its card."),
        ("bolt.circle", "Automatic updates", "Off until you turn them on. Updates install on their own after a check, optionally only on Wi-Fi or Ethernet. Never for anything that needs your password, apps that are open, macOS, betas or major upgrades."),
        ("eye.slash", "More ways to hide updates", "Hide one version as before, or now every update from an app, or only its major upgrades. Unhide them any time."),
        ("flask", "Betas for testers", "A beta of \(AppIdentity.name) is offered the next beta. Everyone else only gets full releases."),
    ]

    private var changelog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's new in 2.0").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.changes, id: \.title) { change in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: change.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.title).font(.callout.weight(.semibold))
                            Text(change.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The beam comes in from the left edge, the icon in the middle, and the
    /// spectrum shines down beneath it, behind the name.
    private var stage: some View {
        ZStack(alignment: .top) {
            rays
            // Incoming white light, bright at its head. The HStack's centre is
            // where the beam ends, so rotating it keeps that end on the icon,
            // and growing from the leading edge makes the head travel inward.
            HStack(spacing: 0) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.15), .white],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: Self.beamLength, height: 6)
                    .shadow(color: glow, radius: 8)
                    // White on the light sheet barely shows: a soft dark edge
                    // gives it a shape. Dark mode doesn't need it.
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.28), radius: 2.5, y: 1)
                    .scaleEffect(x: beam ? 1 : 0, anchor: .leading)
                Color.clear.frame(width: Self.beamLength, height: 6)
            }
            .rotationEffect(.degrees(Self.beamAngle))
            .opacity(ballGone ? 0.3 : (beam ? 1 : 0))
            .offset(y: Self.iconCentre - 3)
            icons.offset(y: Self.iconCentre - Self.iconSize / 2)
            // The explosion: a ball of white light that covers the swap, and a
            // shock ring, both clearing outward.
            Circle()
                .fill(RadialGradient(colors: [.white, .white, .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: 75))
                .frame(width: 150, height: 150)
                .shadow(color: glow, radius: 20)
                .scaleEffect(ballGone ? 3 : (ball ? 1.3 : 0.05))
                .opacity(ballGone ? 0 : (ball ? 1 : 0))
                .offset(y: Self.iconCentre - 75)
            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 120, height: 120)
                .shadow(color: glow, radius: 6)
                .scaleEffect(ballGone ? 3.4 : (ball ? 0.9 : 0.2))
                .opacity(ballGone ? 0 : (ball ? 0.9 : 0))
                .offset(y: Self.iconCentre - 60)
            ZStack {
                Text("UpdateScout")
                    .opacity(renamed ? 0 : 1).blur(radius: renamed ? 8 : 0)
                    .scaleEffect(renamed ? 0.92 : 1)
                Text(AppIdentity.name)
                    .opacity(renamed ? 1 : 0).blur(radius: renamed ? 0 : 8)
                    .scaleEffect(renamed ? 1 : 1.08)
            }
            .font(.largeTitle.weight(.bold))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .offset(y: 134)
        }
    }

    /// White light needs a halo to show on the light pop-up; in dark mode it
    /// glows white.
    private var glow: Color {
        scheme == .dark ? .white : Color(.displayP3, red: 0.62, green: 0.66, blue: 0.86).opacity(0.7)
    }

    private var icons: some View {
        ZStack {
            if let legacy = Self.legacyIcon {
                Image(nsImage: legacy)
                    .resizable().interpolation(.high)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .opacity(morphed ? 0 : 1)
                    .scaleEffect(hit ? 1.1 : 1)
            }
            AppLogo(size: Self.iconSize)
                .opacity(morphed || Self.legacyIcon == nil ? 1 : 0)
                .scaleEffect(ballGone ? 1 : 1.2)
                .shadow(color: .white.opacity(settled ? 0.5 : 0), radius: 12)
        }
    }

    /// Six wedges of colour fanning downward from the icon. Each sits in a
    /// VStack whose centre is the wedge's tip, so rotating it pivots there.
    private var rays: some View {
        ZStack {
            ForEach(Array(PrismBlur.spectrum.enumerated()), id: \.offset) { index, color in
                VStack(spacing: 0) {
                    Color.clear.frame(width: 60, height: Self.rayLength)
                    RayWedge()
                        .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 60, height: Self.rayLength)
                        .blur(radius: 5)
                        .scaleEffect(y: spread ? 1 : 0, anchor: .top)
                }
                .rotationEffect(.degrees(spread ? Double(index) * 11 - 27.5 : 0))
            }
        }
        .opacity(spread ? (breathe ? 0.85 : (settled ? 0.6 : 1)) : 0)
        .offset(y: Self.iconCentre - Self.rayLength)
    }

    private func play() async {
        guard !reduceMotion else {
            beam = true; morphed = true; ballGone = true; spread = true; renamed = true; settled = true
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        // The beam travels in, speeding up toward the icon.
        withAnimation(.easeIn(duration: 1.2)) { beam = true }
        try? await Task.sleep(for: .milliseconds(1200))
        // Impact: the old icon jolts and explodes into white light.
        withAnimation(.spring(duration: 0.25, bounce: 0.5)) { hit = true }
        withAnimation(.easeOut(duration: 0.35)) { ball = true }
        try? await Task.sleep(for: .milliseconds(400))
        // Swap the icons while the ball covers them.
        var swap = Transaction(); swap.disablesAnimations = true
        withTransaction(swap) { morphed = true }
        try? await Task.sleep(for: .milliseconds(350))
        // The ball clears outward, revealing the new icon.
        withAnimation(.easeOut(duration: 1.0)) { ballGone = true }
        try? await Task.sleep(for: .milliseconds(450))
        // The prism splits the light into colour.
        withAnimation(.spring(duration: 1.8, bounce: 0.15)) { spread = true }
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeInOut(duration: 0.9)) { renamed = true }
        try? await Task.sleep(for: .milliseconds(1100))
        withAnimation(.easeOut(duration: 0.8)) { settled = true }
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
    }
}

/// A narrow tip at the top widening toward the bottom: one ray of colour.
private struct RayWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
