{
  description = "dmurko's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Shared Claude Code configuration for Niteo
    niteo-claude.url = "github:teamniteo/claude";
    niteo-claude.inputs.mcp-nixos.follows = "mcp-nixos";
    mcp-nixos.url = "github:utensils/mcp-nixos/v2.3.1";

    # LLM agents (claude-code, codex, etc.) - daily updated builds
    llm-agents.url = "github:numtide/llm-agents.nix";

    devenv.url = "github:cachix/devenv";

  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nix-darwin, home-manager, niteo-claude, mcp-nixos, llm-agents, devenv }:
  let

    homeconfig = { pkgs, lib, ... }:
    let
      pkgs-unstable = import nixpkgs-unstable {
        system = "aarch64-darwin";
        config.allowUnfree = true;
      };
    in {
      # Home Manager configuration
      # https://nix-community.github.io/home-manager/
      home.homeDirectory = lib.mkForce "/Users/dejanmurko";
      home.stateVersion = "25.11";
      programs.home-manager.enable = true;
      programs.htop.enable = true;
      programs.bat.enable = true;

      # Software I can't live without
      home.packages = with pkgs; [
        inputs.devenv.packages.aarch64-darwin.devenv
        cachix
        atuin
        bat
        gh
        nodejs_24
      ];

      programs.vim.enable = true;

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      programs.git = {
        enable = true;
        settings = {
          user = {
            name = "Dejan Murko";
            email = "dmurko@users.noreply.github.com";
          };
          alias = {
            ap = "add -p";
            st = "status";
            ci = "commit";
            co = "checkout";
            df = "diff";
            l = "log";
            ll = "log -p";
            rehab = "reset origin/main --hard";
          };
          branch = {
            autosetuprebase = "always";
          };
          help = {
            autocorrect = 20;
          };
          init = {
            defaultBranch = "main";
          };
          push = {
            default = "simple";
          };
        };
        ignores = [
          # Packages: it's better to unpack these files and commit the raw source
          # git has its own built in compression methods
          "*.7z"
          "*.dmg"
          "*.gz"
          "*.iso"
          "*.jar"
          "*.rar"
          "*.tar"
          "*.zip"

          # OS generated files
          ".DS_Store"
          ".DS_Store?"
          "ehthumbs.db"
          "Icon\r"
          "Thumbs.db"

          # VS Code
          "vscode/History/"
          "vscode/globalStorage/"
          "vscode/workspaceStorage/"

          # Secrets
          "ssh_config_private"

          # AI tooling
          "**/.claude/settings.local.json"
        ];
      };

      programs.diff-so-fancy = {
        enable = true;
        enableGitIntegration = true;
      };

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks."*" = {
          identityAgent = "/Users/dejanmurko/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
        };
      };


      programs.zsh = {
        enable = true;
        autosuggestion.enable = true;
        enableCompletion = true;
        oh-my-zsh = {
          enable = true;
          theme = "robbyrussell";
          plugins = ["git" "sudo" "direnv"];
        };
        sessionVariables = {
          LC_ALL = "en_US.UTF-8";
          LANG = "en_US.UTF-8";
          EDITOR = "~/.editor";
          AGENT_BROWSER_IDLE_TIMEOUT_MS = "300000";

          # Enable a few neat OMZ features
          HYPHEN_INSENSITIVE = "true";
          COMPLETION_WAITING_DOTS = "true";

          # Disable generation of .pyc files
          # https://docs.python-guide.org/writing/gotchas/#disabling-bytecode-pyc-files
          PYTHONDONTWRITEBYTECODE = "0";
        };
        shellAliases = {
          cat = "bat";
          nixre = "sudo darwin-rebuild switch --flake ~/Work/dotfiles#Dejans-Air";
          nixcfg = "code ~/Work/dotfiles";
          nixgc = "nix-collect-garbage -d";
          nixdu = "du -shx /nix/store ";
          history = "atuin search -i";
        };
        history = {
          append = true;
          share = true;
        };
        initContent = ''
          eval "$(atuin init zsh --disable-up-arrow)"
          [[ -f ~/Work/dotfiles/.secrets.env ]] && source ~/Work/dotfiles/.secrets.env

          function edithosts {
              export EDITOR="code --wait"
              sudo -e /etc/hosts
              echo "* Successfully edited /etc/hosts"
              sudo dscacheutil -flushcache && echo "* Flushed local DNS cache"
          }   
        '';
      };

    programs.claude-code = {
        enable = true;
        package = llm-agents.packages.aarch64-darwin.claude-code;

        # Get team MCPs from teamniteo/claude
        mcpServers = niteo-claude.lib.mcpServers pkgs // {
          # OAuth: authenticate via `/mcp` in Claude Code after rebuild.
          # https://docs.ahrefs.com/mcp/docs/claude-code
          ahrefs = {
            type = "http";
            url = "https://api.ahrefs.com/mcp/mcp";
          };

          dataforseo = {
            command = "${pkgs.nodejs}/bin/npx";
            args = [ "-y" "dataforseo-mcp-server" ];
            env = {
              DATAFORSEO_USERNAME = "\${DATAFORSEO_USERNAME}";
              DATAFORSEO_PASSWORD = "\${DATAFORSEO_PASSWORD}";
            };
          };

          # Google Search Console MCP (OAuth mode).
          # https://suganthan.com/blog/google-search-console-mcp-server/
          gsc = {
            command = "${pkgs.nodejs}/bin/npx";
            args = [ "-y" "suganthan-gsc-mcp" ];
            env = {
              GSC_AUTH_MODE = "oauth";
              GSC_OAUTH_SECRETS_FILE = "\${GSC_OAUTH_SECRETS_FILE}";
              GSC_SITE_URL = "\${GSC_SITE_URL}";
            };
          };

          # Plausible Analytics MCP (remote hosted by Sentry).
          # https://github.com/getsentry/plausible-mcp
          plausible = {
            type = "http";
            url = "https://plausible-mcp.sentry.dev/mcp";
            headers = {
              Authorization = "Bearer \${PLAUSIBLE_API_KEY}";
            };
          };
        };

        settings = {

          # Register extra plugin marketplaces
          extraKnownMarketplaces = {
            hakuto = {
              source = {
                source = "github";
                repo = "teamniteo/hakuto";
              };
            };
          };

          # Get team Plugins from teamniteo/claude
          enabledPlugins = niteo-claude.lib.enabledPlugins // {
            "hakuto@hakuto" = true;
          };

          # Get team Permissions from teamniteo/claude
          permissions.allow = niteo-claude.lib.permissions.allow ++ [

            # Auto-allow read-only commands in common directories
            "Read(~/Work/*)"
            "Bash(cat ~/Work/*)"
            "Bash(head ~/Work/*)"
            "Bash(ls ~/Work/*)"
            "Bash(tail ~/Work/*)"
          ];
        };

        # Personal CLAUDE.md content
        memory.text = ''
          # About the User

          Dejan Murko (dmurko) - Co-Founder and Product Lead of Niteo, a bootstrapped SaaS studio founded in 2007, based in Europe. Co-Founder and Product Lead of Mayet, a bootstrapped company building software solutions for the biotech and pharma industry.

          - Believes great software should be self-explanatory. Prioritizes intuitive UI and accessibility over design sophistication.
          - Values consistency as a design principle. Reusable patterns, predictable behavior, no surprises.
          - Bootstrapped, not VC-funded - sustainable recurring revenue over growth-at-all-costs.
          - Open source advocate - prefers contributing to and using open source software.
          - Effectiveness over productivity - focus on impact, not hours.

          **GitHub:** github.com/dmurko - use the GitHub MCP to access private repos when needed.
          **Workstation:** github.com/dmurko/dotfiles - usually invokes Claude from his nix-darwin-powered MacBook defined in these dotfiles.
        '';
      };

      # Claude Code mutates ~/.claude/settings.json at runtime (theme, onboarding,
      # permission approvals). home-manager places it as a read-only /nix/store
      # symlink, which causes EACCES on write. After each rebuild, replace the
      # symlink with a mutable copy. Note: runtime writes (between rebuilds) are
      # overwritten on the next rebuild — home-manager backs the mutated file up
      # to ~/.claude/settings.json.backup (via home-manager.backupFileExtension)
      # if you need to recover.
      home.activation.claudeSettingsWritable = lib.hm.dag.entryAfter ["writeBoundary"] ''
        settings="$HOME/.claude/settings.json"
        if [ -L "$settings" ]; then
          target="$(readlink "$settings")"
          rm "$settings"
          cp "$target" "$settings"
          chmod u+w "$settings"
        fi
      '';

      # Don't show the "Last login" message for every new terminal.
      home.file.".hushlogin" = {
        text = "";
      };

      # Create config files in ~/
      home.file = {
        ".editor" = {
          executable = true;
          text = ''
            #!/bin/bash
            # https://github.com/microsoft/vscode/issues/68579#issuecomment-463039009
            code --wait "$@"
            open -a Terminal
          '';
        };

        # Supply-chain protection: refuse npm/Bun/PyPI packages younger than 7
        # days, so freshly-published malicious versions get caught before we
        # install. pip key requires pip 26.0+; uv duration syntax requires uv
        # 0.9.17+.
        ".npmrc".text = ''
          min-release-age=7
          minimum-release-age=10080
          save-exact=true
        '';
        ".bunfig.toml".text = ''
          [install]
          minimumReleaseAge = 604800
        '';
        ".config/uv/uv.toml".text = ''
          exclude-newer = "7 days"
        '';
        ".config/pip/pip.conf".text = ''
          [install]
          uploaded-prior-to = P7D
        '';
      };
      
    };
    configuration = { pkgs, ... }: {
      # Enable touch ID authentication for sudo.
      security.pam.services.sudo_local.touchIdAuth = true;

      # make sure firewall is up & running
      networking.applicationFirewall.enable = true;
      networking.applicationFirewall.enableStealthMode = true;

        # Personalization
        system.primaryUser = "dejanmurko";
        networking.hostName = "Dejans-Air";
        system.defaults.dock.autohide = true;
        system.defaults.dock.orientation = "left";
        system.defaults.dock.tilesize = 40;
        system.defaults.finder._FXShowPosixPathInTitle = false;
        system.defaults.finder.AppleShowAllExtensions = true;
        system.defaults.finder.AppleShowAllFiles = false;
        system.defaults.finder.ShowPathbar = true;
        system.defaults.finder.ShowStatusBar = true;
        system.defaults.finder.FXPreferredViewStyle = "clmv";
        system.defaults.loginwindow.GuestEnabled = false;
        system.defaults.finder.FXDefaultSearchScope = "SCcf"; # search current folder by default
        system.defaults.NSGlobalDomain.AppleShowScrollBars = "WhenScrolling";
        system.defaults.NSGlobalDomain.AppleScrollerPagingBehavior = true;
        system.defaults.finder.FXEnableExtensionChangeWarning = false;
        system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
        system.defaults.NSGlobalDomain.KeyRepeat = 2;
        system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
        system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;
        system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;
        system.defaults.NSGlobalDomain.NSTableViewDefaultSizeMode = 2;
        system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint = true;
        system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint2 = true;
        system.defaults.trackpad.FirstClickThreshold = 0;
        system.defaults.trackpad.SecondClickThreshold = 0;
        system.keyboard.enableKeyMapping = true;
        system.keyboard.nonUS.remapTilde = true;
        system.defaults.screencapture.disable-shadow = false;
        system.defaults.screensaver.askForPasswordDelay = 1;

      # Use nix from pinned nixpkgs
      nix.settings.trusted-users = [ "@admin dejanmurko" ];
      nix.package = pkgs.nix;

      # Using flakes instead of channels
      nix.settings.nix-path = ["nixpkgs=flake:nixpkgs"];
      nix.channel.enable = false;

      # Allow licensed binaries
      nixpkgs.config.allowUnfree = true;

      # Enable CGO for direnv (required for -linkmode=external)
      nixpkgs.overlays = [
        (_final: prev: {
          direnv = prev.direnv.overrideAttrs (old: {
            env = (old.env or { }) // {
              CGO_ENABLED = 1;
            };
            doCheck = false;
          });
        })
      ];

      # Save disk space
      nix.optimise.automatic = true;

      # Longer log output on errors
      nix.settings.log-lines = 25;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Configure Cachix
      nix.settings.substituters = [
        "https://cache.nixos.org"
        "https://devenv.cachix.org"
        "https://niteo.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "niteo.cachix.org-1:GUFNjJDCE199FDtgkG3ECLrAInFZEDJW2jq2BUQBFYY="
      ];

      # set netrc for automatic login processes (e.g. for cachix)
      nix.settings.netrc-file = "/Users/dejanmurko/.config/nix/netrc";

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Dejans-Air
    darwinConfigurations."Dejans-Air" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        home-manager.darwinModules.home-manager  {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.dejanmurko = homeconfig;
            home-manager.backupFileExtension = ".backup";
            home-manager.extraSpecialArgs = {
              inherit niteo-claude llm-agents;
            };
        }
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."Dejans-Air".pkgs;

    # Support using parts of the config elsewhere
    homeconfig = homeconfig;
  };
}
