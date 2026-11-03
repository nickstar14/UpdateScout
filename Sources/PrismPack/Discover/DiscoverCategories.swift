import SwiftUI

/// Homebrew casks carry no categories, so Discover ships its own mapping for
/// the popular ones (from the 30-day install counts, October 2026), then
/// guesses the rest from each cask's description (Phase 10, Nick: "list, then
/// a guess"). About 80% of non-font casks land in a category; the rest still
/// show in Featured, New and search.
enum DiscoverCategories {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case ai = "AI", audio = "Audio & Music", browsers = "Browsers", cloud = "Cloud & Storage",
             communication = "Communication", design = "Design", developer = "Developer Tools",
             games = "Games", menuBar = "Menu Bar", productivity = "Productivity",
             utilities = "Utilities", video = "Video"
        var id: String { rawValue }

        /// The sidebar dot.
        var color: Color {
            switch self {
            case .ai: .purple
            case .audio: .pink
            case .browsers: .blue
            case .cloud: .cyan
            case .communication: .green
            case .design: .orange
            case .developer: .indigo
            case .games: .red
            case .menuBar: .gray
            case .productivity: Theme.lemon
            case .utilities: .teal
            case .video: .brown
            }
        }
    }

    /// The hand-made list first, then the guess.
    static func category(of entry: DiscoverEntry) -> Category? {
        map[entry.name] ?? guess([entry.summary, entry.title].compactMap { $0 }.joined(separator: " "))
    }

    /// First rule that matches wins, so the narrow ones come first. Tried
    /// against all of Homebrew's casks (31 Oct 2026) and spot-checked.
    static func guess(_ text: String) -> Category? {
        let range = NSRange(text.startIndex..., in: text)
        return rules.first { $0.1.firstMatch(in: text, range: range) != nil }?.0
    }

    private static let rules: [(Category, NSRegularExpression)] = ([
        (.menuBar, #"menu ?bar|status bar|\bnotch\b|\bdock\b"#),
        // "Bluetooth Low Energy browser" and "S3 bucket browser" aren't web browsers.
        (.browsers, #"^(?!.*(bluetooth|database|file|data\b|\blog|ldap|sqlite|\bs3\b|bucket)).*\bbrowser\b"#),
        (.ai, #"\bai\b|\bllms?\b|chatgpt|\bgpt|\bclaude\b|gemini|copilot|machine learning|language models?|\bagents?\b|chatbot|neural|transcri"#),
        (.games, #"\bgames?\b|gaming|\bsteam\b|minecraft|\bchess\b|\bpuzzle"#),
        (.communication, #"\bchat\b|messag|e-?mail|video ?conferenc|\bmeetings?\b|\bvoip\b|\bcalls?\b|telegram|whatsapp|\birc\b|social|slack|discord"#),
        (.audio, #"audio|music|\bsound|podcast|\bradio\b|\bmidi\b|\bdaw\b|synth|equali[sz]|\bmp3\b|\bdj\b|\bvst\b|speaker|\bguitar|\bpiano"#),
        (.video, #"video|movie|media (player|center|server)|\bplayer\b|stream|screen ?record|youtube|subtitle|\biptv\b|\btv\b|\bdvd\b|blu-ray|webcam|\bcamera"#),
        (.design, #"design|\bgraphics?\b|\bimages?\b|photo|drawing|illustrat|\b3d\b|\bcad\b|vector|\bfonts?\b|\bcolou?rs?\b|\bicons?\b|sketch|animation|render|pixel|\bpaint"#),
        (.cloud, #"cloud|\bsync|backup|file (sharing|transfer)|\bs?ftp\b|\bnas\b|\bdrive\b|storage|torrent|download manager|\bs3\b"#),
        (.developer, #"\bides?\b|code editor|editor for|developer|development|programming|\bcode\b|terminal|\bgit\b|database|\bsql|\bapi\b|docker|kubernetes|container|debug|compiler|\bsdk\b|emulat|simulat|virtual machine|virtuali[sz]|\bssh\b|regex|\bjson\b|\bhttp|\brest\b|xcode|android|javascript|python|\brust\b|\bjava\b|devops|\bcli\b|command[- ]line|\bshell\b|scripting|\bnode"#),
        (.productivity, #"\bnotes?\b|note-taking|\btasks?\b|to-?do|calendar|office|documents?|spreadsheet|\bpdf\b|writ(ing|er)|markdown|password|clipboard|launcher|productivity|time ?track|reading|e-?books?|mind ?map|project management|financ|budget|accounting|\bwiki|knowledge|\bscan"#),
        (.utilities, #"utility|utilities|\bwindows?\b|keyboard|\bmouse\b|trackpad|\bsystem\b|monitor|battery|\bdisk|clean|uninstall|\bvpn\b|screenshot|archiv|\bzip\b|remote|display|\bscreen|file manager|finder|security|antivirus|malware|firewall|network|\bfiles?\b|tool|helper|\bdriver"#),
    ] as [(Category, String)]).map { ($0.0, try! NSRegularExpression(pattern: $0.1, options: [.caseInsensitive])) }

    private static let map: [String: Category] = {
        var map: [String: Category] = [:]
        func add(_ category: Category, _ tokens: String) {
            for token in tokens.split(whereSeparator: \.isWhitespace) { map[String(token)] = category }
        }
        add(.ai, """
            chatgpt claude google-gemini gemini lm-studio ollama-app anythingllm msty jan perplexity
            granola macwhisper superwhisper wispr-flow voiceink
            """)
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
            sentry-cli codeql vercel termius tabby hammerspoon homebrew-app applite caskhub
            dbx sqlcl nova textmate 1password-cli secretive
            """)
        add(.productivity, """
            obsidian notion libreoffice microsoft-office microsoft-word microsoft-excel microsoft-powerpoint
            microsoft-outlook microsoft-onenote onlyoffice wpsoffice-cn raycast alfred 1password bitwarden
            keepassxc zotero anki calibre typora markedit macdown-3000 notion-calendar linear todoist things3
            fantastical adobe-acrobat-reader skim netnewswire espanso bettertouchtool
            mactex mactex-no-gui basictex
            """)
        add(.audio, """
            spotify audacity musescore background-music eqmac blackhole-2ch blackhole-16ch blackhole-64ch
            notunes
            """)
        add(.video, """
            vlc iina obs handbrake-app losslesscut mkvtoolnix-app capcut stremio jellyfin plex moonlight
            """)
        add(.design, """
            blender gimp inkscape krita figma affinity adobe-creative-cloud upscayl draw-things imageoptim
            freecad openscad@snapshot kicad bambu-studio orcaslicer prusaslicer qgis sf-symbols icon-composer
            """)
        add(.games, """
            steam epic-games prismlauncher minecraft roblox robloxstudio crossover whisky porting-kit dolphin
            lunar-client
            """)
        add(.communication, """
            slack discord zoom microsoft-teams whatsapp telegram telegram-desktop signal wechat thunderbird
            proton-mail element skype webex mattermost rocket-chat beeper messenger viber
            """)
        add(.cloud, """
            google-drive dropbox onedrive nextcloud cryptomator syncthing-app transmission cyberduck mounty
            localsend synology-drive proton-drive transmit
            """)
        add(.menuBar, """
            stats hiddenbar jordanbaird-ice thaw bartender itsycal meetingbar swiftbar istat-menus caffeine
            keepingyouawake aldente
            """)
        add(.utilities, """
            rectangle maccy betterdisplay monitorcontrol alt-tab karabiner-elements linearmouse mos
            scroll-reverser mac-mouse-fix middleclick logi-options+ appcleaner pearcleaner keka
            the-unarchiver macpacker openmtp android-file-transfer balenaetcher raspberry-pi-imager macfuse
            fuse-t tailscale-app cloudflare-warp protonvpn nordvpn tunnelblick openvpn-connect aws-vpn-client
            lulu knockknock shottr keycastr cleanshot grandperspective onyx macs-fan-control amethyst
            nikitabobko/tap/aerospace dockdoor loop lunar finicky qlmarkdown syntax-highlight
            input-source-pro keyboardcleantool clop crystalfetch anydesk rustdesk teamviewer
            realvnc-connect-viewer tigervnc windows-app kde-connect displaylink purge ubersicht
            """)
        return map
    }()
}
