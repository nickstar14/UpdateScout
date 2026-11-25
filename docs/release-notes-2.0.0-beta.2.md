## PrismPack 2.0.0 beta 2

Fixes from the first beta.

- **One copy, always the newest.** A second launch shows the first copy's window. A newer build closes the older one. No second menu bar icon or window.
- **Homebrew apps that wouldn't update.** Apps Homebrew can't replace on its own (owned by another user or root) now wait for you and ask for your password on Update, instead of failing in the background. A leftover copy from a failed upgrade gets a **Repair and Update** button, failures show Homebrew's real message, and an automatic failure of this kind sends a notification.
- **No endless retries.** After two failures in a row, automatic updates stop trying that app until a new version arrives. Updating by hand still works.
- **One password prompt, and it says why.** Both prompts are the same native alert and say what the password is for and what set it off ("to update Signal, which you started"). Skip is now Cancel.
- **Notifications** have Open and Dismiss buttons and are removed from Notification Center once used.
- **Daily cleanup.** Once a day: Homebrew's old versions and downloads, and the pip and npm caches. Logged in Activity, nothing installed is removed, can be turned off in Settings.
- **Set up window.** First launch opens Homebrew and mas first, then optional Full Disk Access with what it is for. Settings shows "Granted" and how to turn it off. The wording follows your macOS version.
- **Look-alikes.** Different-named apps that share a bundle ID (two editions of one product) are shown as look-alikes, with nothing suggested to remove.
- **Check for Updates** moved to the PrismPack section at the top of Settings.

**Full Disk Access on macOS 27.3 is still in beta.** Apple changed how it works in the 27.3 beta (a new list, adding apps with + instead of dragging, optional folder-by-folder access). PrismPack's steps for 27.3 may change until 27.3 is released. macOS 15 and 26 are unchanged.

This is a beta.
