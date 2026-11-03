# Liquid Glass for macOS apps: a reusable guide (from PrismPack 2.0)

Written 3 Nov 2026 for reuse in other apps. Code is from PrismPack's
`Sources/PrismPack/Views/Style.swift` and `UpdatesWindow.swift`; copy the
helpers, rename them. Marked **[built]** = used and checked in PrismPack,
**[SDK]** = confirmed in the macOS 27 SDK headers on this Mac but not run,
**[idea]** = my suggestion, not built here. Deployment target in PrismPack is
macOS 15, so every glass call sits behind `#available(macOS 26.0, *)` with a
material fallback.

## 1. Rules that held up

1. **Use the standard controls first.** A `NavigationSplitView`, `List` with
   `.listStyle(.sidebar)`, `.toolbar`, `Button`, sheets and popovers get Liquid
   Glass and the macOS 27 look for free. Only draw your own glass where the
   system has no control for it (capsule search field, segmented bubble).
2. **Glass is for controls and chrome, not content.** Never stack glass on
   glass; rows inside a glass card stay plain **[built]**.
3. **One tint per meaning.** Tint glass with a colour that means something
   (a section, destructive red); leave everything else clear **[built]**.
4. **Don't hard-code window or card radii for the window itself.** macOS 27
   exposes `NSViewCornerConfiguration` / `effectiveCornerRadii` **[SDK]**;
   keep a smaller concentric radius for cards (PrismPack: 16).
5. **Every clickable thing is a real `Button`** with an accessibility label
   (also what makes UI automation work) **[built]**.
6. Check light, dark and Reduce Transparency. Fallback on macOS 15 is
   `.regularMaterial` plus a hairline stroke **[built]**.

## 2. The building blocks

### Availability wrapper (use for everything)
```swift
@ViewBuilder func glassOrMaterial<S: Shape>(_ shape: S) -> some View {
    if #available(macOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
    else { shape.fill(.regularMaterial) }
}
```

### Buttons **[built]**
- `.buttonStyle(.glass)` for normal glass buttons; `.buttonStyle(.glassProminent)`
  with `.tint(color)` for the one primary action per screen.
- Destructive: `.buttonStyle(.glass).tint(.red)` with a red label.
- Fallback below 26: `.bordered` / `.borderedProminent`.
- Wrap in view extensions (`.glass()`, `.glassProminent(_:)`,
  `.glassDestructive()`) so every screen is one word.

### Circular icon buttons: close, refresh, sidebar **[built]**
```swift
Button(action: act) {
    Image(systemName: "arrow.clockwise")
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 24, height: 24)
        .background { Circle().fill(.clear).glassEffect(.regular.interactive(), in: Circle()) }
        .contentShape(Circle())
}
.buttonStyle(.plain).help("Refresh").accessibilityLabel("Refresh")
```
`.interactive()` gives the press and hover response. For a refresh that
spins, animate the symbol (`.symbolEffect(.rotate, isActive: busy)`) **[idea]**
and swap the label to "Checking…" while busy **[built]**. In a toolbar, use a
plain `Button { } label: { Label(…) }` and let the toolbar draw the glass.

### Capsule field (search, plain text) and stepper **[built]**
A `HStack` with `.background { Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule()) }`.
The stepper is the same capsule with − and + buttons inside (`GlassStepper`).

### Segmented control with a sliding glass bubble **[built]**
`GlassSegmented`: segments in an `HStack`; behind the selected one a
`Capsule().glassEffect(.regular.interactive())` positioned from each
segment's frame (read with a named coordinate space). Selection moves the
bubble at once; the bound value follows ~0.12 s later so heavy pages don't
stall the slide. Drag the bubble and snap to the nearest segment on release.

### Toggles / switches **[idea]**
The system `Toggle` with `.toggleStyle(.switch)` is already glass on macOS 26+;
use it unchanged. PrismPack only uses `.checkbox` for list selection. If a
custom one is needed: a capsule track (`glassEffect`, tinted green when on)
with a white circle knob that slides with `.animation(.snappy)`, and keep it a
real `Toggle` (custom `ToggleStyle`) so VoiceOver and keyboard work.

### Panels and cards **[built]**
```swift
let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
content.background { Color.clear.glassEffect(.regular.tint(color.opacity(0.32)), in: shape) }
       .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
       .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
```
Tint opacity 0.3 reads as colour without losing the glass; fixed, not tied to
any user slider.

### Icon tiles **[built]**
Small rounded square, `.glassEffect(.regular.tint(color.opacity(0.55)), in: shape)`,
SF Symbol in white on top. Solid colour fill on macOS 15.

### Sidebar **[built]**
`NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)` with
standard `Label` rows (honours the system sidebar-size setting). macOS 27
draws it edge to edge, no shadow, coloured icons by accent. Keep the header
(icon, name, version) at the top; never put actions at the bottom of the
sidebar, except pinned rows via `safeAreaBar` (below) **[built]**.

**Sidebar toggle.** The toggle belongs in the sidebar's own toolbar section,
left of the divider, and it stays put when the sidebar's grey hides. Normally
the system adds it. If it doesn't (a window you build yourself with
`NSWindow(contentViewController: NSHostingController(...))` and
`sceneBridgingOptions = [.toolbars, .title]` did not), ask for it:
```swift
.toolbar {
    if #available(macOS 26.0, *) { DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation) }
    else { ToolbarItem(placement: .navigation) { /* own Button toggling columnVisibility */ } }
}
```
`DefaultToolbarItem` and `ToolbarDefaultItemKind.sidebarToggle` are in the
SDK **[SDK]**; `.toolbar(removing: .sidebarToggle)` removes the system one.
PrismPack's first version used a plain `ToolbarItem`, which landed in the
detail toolbar (wrong on macOS 27). The `DefaultToolbarItem` version compiles;
its position is **checked in the next build, not yet seen.** If the system
still puts it wrong, the fallback is an AppKit `NSToolbar` with
`NSToolbarToggleSidebarItemIdentifier` followed by
`NSToolbarSidebarTrackingSeparatorItemIdentifier` **[SDK]**.

### Pinned headers and scroll edges **[built]**
```swift
self.safeAreaBar(edge: .top, spacing: 0) { header }
    .scrollEdgeEffectStyle(.soft, for: .top)
```
Content scrolls under the bar and the system draws the glass edge effect.
Set the style explicitly; `automatic` resolved to `hard` on some SDKs. Below
26 use `safeAreaInset` with `.background(.bar)`. Never put
`fixedSize(horizontal:false, vertical:true)` text inside a pinned header: it
measured at zero width and made the page thousands of points tall.

### Pop-ups and slide-overs
- **Popover** (`.popover(isPresented:arrowEdge:)`) **[built]**: system glass,
  nothing to add. Put a small glass close circle top-right (above) and
  `.keyboardShortcut(.cancelAction)`.
- **Sheet** **[built]**: system glass. Block dismissal with
  `.interactiveDismissDisabled()` only for must-answer sheets.
- **Slide-over / inspector** **[idea]**: `.inspector(isPresented:)` gives a
  trailing glass column that slides in; `.inspectorColumnWidth(min:ideal:max:)`
  sets width. For a floating card instead, overlay a panel with the card
  recipe above plus `.transition(.move(edge: .trailing).combined(with: .opacity))`
  inside `withAnimation(.snappy)`. Prefer the inspector; it behaves like the
  system.
- **Large preview inside a pop-up** **[built]**: swap content inside the pop-up
  (Back, ‹ n of 3 ›, arrow keys, Esc) instead of opening another window.

### Morphing between glass shapes **[idea]**
`GlassEffectContainer { … }` with `.glassEffectID(id, in: namespace)` lets
nearby glass shapes merge and morph. Not used in PrismPack; try it for a
button that expands into a menu.

## 3. Window background wash **[built]**
A `ZStack` of `Color(nsColor: .windowBackgroundColor)` with a tinted wash at
low opacity (silver in light, midnight in dark) behind the detail column;
glass cards pick it up. PrismPack's own "Glass" slider that scaled this wash
was **removed** (3 Nov 2026): it never changed the buttons, and macOS 27 has
its own Liquid Glass setting. The window background is now the plain system one.

## 4. Special effects (not defaults)
- **Rainbow primary button (Update All) [built]:** `.buttonStyle(.glass)` plus
  a `Capsule` filled with a six-colour `LinearGradient`, `.blur(radius: 6)`,
  `.opacity(0.22)`, `.padding(2)`, as a `.background` with
  `allowsHitTesting(false)`. The glass refracts the colour. Use once per app.
- **Glass key badge [built]:** `Image(systemName:)` on a `Circle` glass, over
  the corner of an app icon (like the macOS app badge). For `NSImage` icons
  (alerts) real glass cannot render: draw it by hand (frosted fill, bright
  top edge fading down).

## 5. Menus, icons, extras (macOS 27)
- Menu item icons hidden by default (apps linked against the 26 SDK or later);
  force with `NSMenuItem.preferredImageVisibility = .visible` **[SDK]**.
- App icon: an Icon Composer `.icon` file with separate layers; compile with
  `actool`; PrismPack's `build-app.sh` also patches the linked-SDK version so
  AppKit uses the new UI **[built]**.
- Menu bar status item: `NSStatusItem` (not `MenuBarExtra`) when you need
  left-click = window and right-click = menu; keep one item and its
  `autosaveName` so menu bar managers keep its position **[built]**.

## 6. Checklist before shipping
Light, dark, Reduce Transparency; macOS 15 fallback; every control a real
Button with a label; no glass on glass; one prominent action per screen; no
fixed sidebar icon sizes; windows never sized by their pages.
