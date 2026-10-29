import SwiftUI

/// One-time pop-up for people upgrading from UpdateScout (rename plan,
/// section 7; Nick asked for a pop-up with a prism effect instead of a banner).
/// A white beam slowly charges the old icon, it bursts into the new one, and
/// the light falls away below as the icon's six colours, behind the name as
/// it changes. The rays then breathe gently. Reduce Motion shows the end state.
struct RenameWelcome: View {
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beam = false
    @State private var charged = false
    @State private var burst = false
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
            Text("Version 2.0 is much more than an updater. Alongside updates, \(name) now helps you find and install new apps and look after the software you already have. The old name no longer covered all of that.")
            Text("Finding a name that fit, and that nobody else was using, took a while. We chose \(name) because a prism gathers many colours of light into one. \(name) does the same for your software: Homebrew, the App Store, Sparkle apps, Python, npm and more, brought together in one place.")
            Text("Your settings and history carried over.").foregroundStyle(.primary)
        }
        .font(.callout).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What's new in 2.0. Draft for Nick to approve before a beta; Discover,
    /// adoption and duplicates land in Phases 6 and 7, so keep this in step.
    static let changes: [(symbol: String, title: String, detail: String)] = [
        ("macwindow", "A new window", "A sidebar with Updates, Discover, Installed, Activity and Settings, in the macOS 27 Liquid Glass look."),
        ("square.stack.3d.up.fill", "Sections you can fold", "Each source has its own colour and icon, folds away, and has its own Update all button."),
        ("arrow.down.circle", "Several updates at once", "Updates run side by side, each with its own progress and Cancel. Choose how many in Settings."),
        ("key.fill", "One password per batch", "Enter it once for a whole batch. It's kept in memory for that batch only and never saved."),
        ("terminal.fill", "Python and npm", "pipx, uv tools and global npm packages, plus a Tools section for the package managers themselves."),
        ("magnifyingglass", "Discover", "Search for new apps and tools across Homebrew, npm and more, and install them in one click."),
        ("checkmark.circle", "Installed and Activity", "See everything installed in one list, and a history of what was updated, skipped or failed."),
        ("info.circle", "App details", "Click an app for its versions and release notes, and to hide one version, all updates, or only major upgrades."),
        ("triangle", "A new menu bar prism", "Click it to open the window. Right-click for Check Now, Settings and Quit."),
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

    /// The beam comes in from the upper left, the icon in the middle, and the
    /// spectrum shines down beneath it, behind the name.
    private var stage: some View {
        ZStack(alignment: .top) {
            rays
            // Incoming white light. The HStack's centre is the beam's end, so
            // rotating it keeps that end on the icon.
            HStack(spacing: 0) {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 210, height: 6)
                    .shadow(color: .white, radius: 8)
                    .scaleEffect(x: beam ? 1 : 0, anchor: .trailing)
                Color.clear.frame(width: 210, height: 6)
            }
            .rotationEffect(.degrees(22))
            .opacity(settled ? 0.3 : (beam ? 1 : 0))
            .offset(y: Self.iconCentre - 3)
            // Charge, then a burst of light when the icons swap.
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: 90))
                .frame(width: 180, height: 180)
                .scaleEffect(burst ? 2.4 : (charged ? 1 : 0.3))
                .opacity(burst ? 0 : (charged ? 0.95 : 0))
                .offset(y: Self.iconCentre - 90)
            icons.offset(y: Self.iconCentre - Self.iconSize / 2)
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

    private var icons: some View {
        ZStack {
            if let legacy = Self.legacyIcon {
                Image(nsImage: legacy)
                    .resizable().interpolation(.high)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .opacity(morphed ? 0 : 1)
                    .blur(radius: morphed ? 12 : 0)
                    .scaleEffect(morphed ? 0.7 : (charged ? 1.06 : 1))
            }
            AppLogo(size: Self.iconSize)
                .opacity(morphed || Self.legacyIcon == nil ? 1 : 0)
                .blur(radius: morphed ? 0 : 12)
                .scaleEffect(morphed ? 1 : 1.3)
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
            beam = true; morphed = true; spread = true; renamed = true; settled = true
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.easeInOut(duration: 1.4)) { beam = true; charged = true }
        try? await Task.sleep(for: .milliseconds(1400))
        withAnimation(.easeOut(duration: 1.0)) { burst = true }
        withAnimation(.spring(duration: 0.9, bounce: 0.35)) { morphed = true }
        try? await Task.sleep(for: .milliseconds(300))
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
