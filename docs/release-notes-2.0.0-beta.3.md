## PrismPack 2.0.0 beta 3

Fixes and a better Activity page.

- **Apps that Homebrew wrongly calls outdated.** Homebrew can list an app as outdated when the installed and latest versions are the same, so "updating" it changes nothing and it stays in the list forever. It can happen to any app or Homebrew package (one known cause: for apps that update themselves, Homebrew compares the app's build number with a download hash in the version). PrismPack now checks for this, so there's no confusion: these are treated as up to date and not offered as updates. Each one is noted once in Activity with a short explanation and a **Copy Homebrew report** button. The app is listed again when a real new version appears.
- **Activity details.** Each Activity entry has a dropdown that rolls open with the exact time, the source, the versions, whether it ran automatically or by you, the command, how long it took, and the version found on disk afterwards. Installs that worked now keep their output too (Show log).
- **Export Activity.** **Export Activity** saves a plain text report (PrismPack, macOS and Homebrew versions, the updates listed, and every entry with its details and log, or only the ticked ones). **Copy to Clipboard** copies a report of the entries you ticked, and **Select All** ticks everything shown. **Clear** removes the ticked entries (it asks first when you clear more than one). Your home folder is shown as `~`, and no passwords are included.
- **Release Notes** opens on the newest version, and keeps your choice if the list loads late.

This is a beta.
