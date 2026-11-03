> **This is a beta.** Download it from this page: UpdateScout 1.8.0's updater does not offer betas. Once you are running it, PrismPack offers you later betas and the final 2.0.0 automatically. Please open an issue if something looks wrong.

## UpdateScout is now PrismPack

Version 2.0 is much more than an updater. Alongside updates, PrismPack helps you find and install new apps, and look after the software you already have. A prism takes a single beam of white light and reveals every colour inside it; PrismPack does the same for your Mac, with each source in its own colour.

**What carries over:** your settings, history, hidden updates, custom and GitHub sources, and the background check.

**What to expect on first launch:**
- The app renames itself to `PrismPack.app` in the same folder and restarts.
- A one-time pop-up explains the new name. You can replay it from the banner on Updates.
- Because the app has a new identity, macOS asks again for notification permission, and Full Disk Access (optional) starts over. Settings → Setup walks you through it.
- Its data folder is now `~/Library/Application Support/PrismPack/`, and the background check runs under the new name.
- If you use a menu bar manager such as Thaw, Ice or Bartender, the prism may need to be placed again once.

## A new window
- A sidebar with **Updates**, **Installed**, **Orphaned App Files**, **Discover**, **Activity** and **Settings**, in the Liquid Glass look on macOS 26 and later, with a simpler look on earlier versions.
- Settings is a page, not a separate window. An app's details open as a pop-up.
- **Cards or a list** on Updates, Installed and Discover, remembered for each page.
- A Light, Dark or System theme.
- The menu bar prism opens the window with a click; right-click it for Check Now, Settings and Quit. ⌘Q asks first, and Close Window keeps PrismPack running in the menu bar.

## Discover
- Find and install new apps and tools from Homebrew, npm, PyPI, crates.io, RubyGems and the editor extension stores (VS Code, VSCodium, Cursor). Fonts can be installed right from Discover.
- Browse what's popular this month, what's new, and apps by category, with search, sorting and cards or a list.
- Each app's page shows its own description and pictures; fonts show a preview and every style.

## Updates
- Sections for Homebrew, the Mac App Store, Sparkle apps, Python (pipx and uv), npm, Rust, Ruby gems, editor extensions, custom sources and a Tools section for the package managers. Apple's own apps are shown as macOS updates and handled by Software Update.
- Update cards preview the release notes and warn about major upgrades, restarts and iPhone/iPad apps.
- Updates run side by side, each with its own progress and Cancel, while each package manager still does one thing at a time. You choose how many run at once in Settings.
- **One password per batch.** It is kept in memory for that batch only, never written to disk, and wiped when the batch ends.
- A progress bar with a percent while a download can be measured, and a step line (verifying, installing…) otherwise. When nothing can be measured, it says so.

## Installed, Duplicates and Homebrew
- Everything on your Mac in one list, showing where each item came from and whether it is up to date. Filter by source and sort by name, size, date or type.
- Update an app, or move it to the Trash, from its details.
- **Duplicates:** two copies of one app, or an App Store app Homebrew also tracks, are shown side by side with versions, sizes and how often you open each. Keep Homebrew's copy in one click. Nothing is removed without asking, and copies go to the Trash.
- **Move apps under Homebrew:** PrismPack spots apps nothing keeps up to date that Homebrew could, checks that Homebrew is really better for each one, and moves it only when you click. You can undo it later.

## Uninstall and clean-up
- Remove an app or package the right way for where it came from. One window shows the app, the files it left in your Library and Homebrew's cleanup list before anything moves. Everything goes to the Trash so you can put it back.
- **Orphaned App Files** lists what removed apps left behind, with size and last-changed date. Nothing is ticked. Keep files, move them to the Trash, or tell PrismPack which app a file belongs to and it is offered when you move that app.
- **Full Disk Access** is optional. It lets PrismPack clear the app data folders macOS protects, and Settings → Setup helps you turn it on.

## You decide what updates
- **Stable or Beta, per app.** Choose which release track each app follows, on its details.
- **Automatic updates** are off until you turn them on. They install after a check, optionally only on Wi-Fi or Ethernet, and never for anything that needs your password, apps that are open, macOS, betas or major upgrades.
- **Hide** one version, every update from an app, or only its major upgrades. Hidden updates don't appear in the list, don't send notifications, and Update All skips them.

## Your own sources
- **Apps on GitHub:** link an app that publishes its releases on GitHub, from Settings or the app's page. Only a download signed by the same developer is installed; unsigned apps need a clear OK first.
- **Custom sources:** a web page with a version number, or a command PrismPack runs. Add one in Settings → Other sources; it is tested before it is saved.

## Activity
A history of checks, updates, installs and removals with search and filters. It stays until you delete it, and failures keep their log so you can retry them.

## Settings
- A search field that finds any setting.
- **Setup** lists the tools PrismPack uses (Homebrew, mas, pipx, Node, Rust and more) with Install and Reinstall.
- **Release notes** for this version and earlier ones, pulled from GitHub.
- **Beta versions** switch to try new PrismPack releases early.

## Light on memory
PrismPack idles at about 15 MB in the menu bar. Closing the window frees much of what it was using, such as Discover's catalogue and pictures.

## Requirements
- macOS 15 or later, on a Mac with Apple silicon.
- Developed and tested on macOS 27. macOS 15 and 26 use the same code with simpler styling; reports are welcome.

## Technical notes
- New bundle ID `com.nickszun.prismpack`, background agent `com.nickszun.prismpack.check`, data in `Application Support/PrismPack/`. The update feed and signing key are unchanged, so updates from 1.8.0 work as before.
