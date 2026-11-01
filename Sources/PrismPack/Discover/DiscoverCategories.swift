import SwiftUI

/// Homebrew casks carry no categories, so Discover ships its own mapping for
/// the popular ones (from the 30-day install counts, October 2026). Casks not
/// listed here still show under Apps and in search; they just have no
/// category chip. Add to it over time.
enum DiscoverCategories {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case browsers = "Browsers", developer = "Developer", productivity = "Productivity",
             media = "Media", communication = "Communication", utilities = "Utilities"
        var id: String { rawValue }

        /// The sidebar dot.
        var color: Color {
            switch self {
            case .browsers: .blue
            case .developer: .indigo
            case .productivity: .yellow
            case .media: .pink
            case .communication: .green
            case .utilities: .cyan
            }
        }
    }

    static func category(ofCask token: String) -> Category? { map[token] }

    private static let map: [String: Category] = {
        var map: [String: Category] = [:]
        func add(_ category: Category, _ tokens: String) {
            for token in tokens.split(whereSeparator: \.isWhitespace) { map[String(token)] = category }
        }
        add(.browsers, """
            google-chrome google-chrome@canary firefox firefox@developer-edition brave-browser microsoft-edge
            zen arc librewolf ungoogled-chromium tor-browser vivaldi opera helium-browser duckduckgo
            thebrowsercompany-dia yandex orion chromium safari-technology-preview floorp waterfox
            """)
        add(.developer, """
            visual-studio-code vscodium cursor zed sublime-text iterm2 ghostty warp kitty wezterm alacritty
            docker-desktop orbstack podman-desktop rancher utm virtualbox multipass vagrant
            android-studio android-platform-tools android-commandlinetools flutter dotnet-sdk dotnet-sdk@8
            temurin temurin@8 temurin@11 temurin@17 temurin@21 temurin@25 zulu@8 zulu@17 zulu@21
            corretto@17 corretto@21 corretto@25 powershell@preview gcloud-cli azure-cli session-manager-plugin
            ngrok postman bruno insomnia dbeaver-community pgadmin4 tableplus sequel-ace mysqlworkbench
            mongodb-compass db-browser-for-sqlite beekeeper-studio redis-insight another-redis-desktop-manager
            datagrip intellij-idea intellij-idea-ce pycharm jetbrains-toolbox xcodes-app github fork sourcetree
            git-credential-manager mitmproxy proxyman wireshark-app godot unity-hub hopper-disassembler
            burp-suite lens openlens freelens headlamp codex claude-code claude-code@latest copilot-cli
            cursor-cli kiro kiro-cli devtunnel postgres-app localstack emacs-app bbedit coteditor meld
            arduino-ide gcc-arm-embedded rstudio quarto r-app miniconda miniforge anaconda xquartz
            sentry-cli codeql vercel termius tabby swiftbar hammerspoon homebrew-app applite caskhub
            dbx sqlcl insomnia nova textmate
            """)
        add(.productivity, """
            obsidian notion libreoffice microsoft-office microsoft-word microsoft-excel microsoft-powerpoint
            microsoft-outlook onlyoffice wpsoffice-cn raycast alfred 1password 1password-cli bitwarden keepassxc
            secretive google-drive dropbox onedrive nextcloud cryptomator syncthing-app zotero anki calibre
            typora markedit macdown-3000 notion-calendar itsycal linear chatgpt claude google-gemini gemini
            lm-studio ollama-app anythingllm granola macwhisper superwhisper wispr-flow voiceink espanso
            meetingbar adobe-acrobat-reader skim netnewswire todoist things3 fantastical bettertouchtool
            mactex mactex-no-gui basictex
            """)
        add(.media, """
            vlc iina spotify obs handbrake-app audacity blender gimp inkscape krita figma affinity
            adobe-creative-cloud musescore losslesscut mkvtoolnix-app upscayl draw-things capcut stremio
            jellyfin imageoptim background-music eqmac blackhole-2ch blackhole-16ch blackhole-64ch
            freecad openscad@snapshot kicad bambu-studio orcaslicer prusaslicer qgis steam epic-games
            prismlauncher minecraft roblox robloxstudio moonlight crossover whisky porting-kit dolphin
            """)
        add(.communication, """
            slack discord zoom microsoft-teams whatsapp telegram telegram-desktop signal wechat thunderbird
            proton-mail element skype webex mattermost rocket-chat beeper messenger viber
            """)
        add(.utilities, """
            rectangle maccy stats betterdisplay monitorcontrol hiddenbar jordanbaird-ice thaw bartender
            alt-tab karabiner-elements linearmouse mos scroll-reverser mac-mouse-fix middleclick
            logi-options+ caffeine keepingyouawake aldente appcleaner pearcleaner keka the-unarchiver
            macpacker localsend openmtp android-file-transfer balenaetcher raspberry-pi-imager macfuse fuse-t
            tailscale-app cloudflare-warp protonvpn nordvpn tunnelblick openvpn-connect aws-vpn-client
            lulu knockknock shottr keycastr cleanshot istat-menus grandperspective onyx macs-fan-control
            amethyst nikitabobko/tap/aerospace dockdoor loop lunar finicky qlmarkdown syntax-highlight
            input-source-pro keyboardcleantool notunes clop crystalfetch transmission cyberduck mounty
            anydesk rustdesk teamviewer realvnc-connect-viewer tigervnc windows-app kde-connect
            displaylink purge ubersicht
            """)
        return map
    }()
}
