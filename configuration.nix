{ config, pkgs, lib, ... }:

let
  username = "student";
  flakeUrl = "github:conweek/csse3010-wsl/main#csse3010-wsl";

  # SSH Key Generation bash script (RUNS AT BOOT UP BUT ENDS EARLY IF ALREADY EXECUTED)
  generateSshKeysScript = pkgs.writeShellScript "csse3010-generate-ssh-keys" ''
    set -euo pipefail
    KEY="/home/${username}/.ssh/id_ed25519"
    if [ -f "$KEY" ]; then
      echo "SSH key already exists, skipping."
      exit 0
    fi
    mkdir -p "/home/${username}/.ssh"
    chmod 700 "/home/${username}/.ssh"
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 \
      -f "$KEY" \
      -N "" \
      -C "${username}@csse3010-wsl"
    chmod 600 "$KEY"
    chmod 644 "$KEY.pub"
    chown -R ${username}:users "/home/${username}/.ssh"
    echo "SSH Key has been generated!"
    echo "Public Key:"
    cat "$KEY.pub"
  '';

  # Interactive first-time user setup (runs in terminal, NOT as a background service)
  firstTimeSetupScript = pkgs.writeShellScriptBin "csse3010-first-setup" ''
    set -euo pipefail

    MARKER="$HOME/.csse3010-user-setup-done"

    if [ -f "$MARKER" ]; then
      echo "First-time setup already completed. To reconfigure git, use: configure-info"
      exit 0
    fi

    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      echo "ERROR: SSH key not found. Please wait for the system to generate it."
      exit 1
    fi

    if [ ! -d "$HOME/csse3010/sourcelib" ]; then
      echo "ERROR: sourcelib not found. Please wait for the system to clone it."
      exit 1
    fi

    echo ""
    echo "======================================"
    echo "   CSSE3010 First-Time User Setup"
    echo "======================================"
    echo ""

    while true; do
      read -rp "Enter your 8 digit UQ student ID (e.g. s48201356): " STUDENT_INPUT
      STUDENT_INPUT="''${STUDENT_INPUT,,}"
      if [[ "$STUDENT_INPUT" =~ ^s[0-9]{8}$ ]]; then
        break
      fi
      echo "Invalid format. Must be 's' followed by 8 digits (e.g. s48201356)."
    done
    STUDENT_ID="''${STUDENT_INPUT:1}"
    UQ_USERNAME="s''${STUDENT_ID:0:7}"

    while true; do
      read -rp "Enter your full name: " FULL_NAME
      if [ -n "$FULL_NAME" ]; then
        break
      fi
      echo "Name cannot be empty."
    done

    EMAIL="$UQ_USERNAME@student.uq.edu.au"

    ${pkgs.git}/bin/git config --global user.name "$FULL_NAME"
    ${pkgs.git}/bin/git config --global user.email "$EMAIL"
    echo ""
    echo "Git configured: $FULL_NAME <$EMAIL>"

    # Make sure students can't Ctrl+C out of the script when trying to copy text
    trap "" INT

    echo ""
    echo "Your SSH public key:"
    echo "------------------------------------------------------------"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo "------------------------------------------------------------"
    echo ""
    echo "Please add this key to the UQ EAIT and Gitea SSH key portals!"
    echo "Links: "
    printf "  \e[1mstudent.eait.uq.edu.au/accounts/sshkeys.ephp\n"
    printf "  csse3010-gitea.uqcloud.net/user/settings/keys\e[0m\n"
    #echo "Please add this key to the UQ EAIT SSH key portal (student.eait.uq.edu.au/accounts/sshkeys.ephp)."
    printf "\e[1mUse Ctrl+Shift+C to copy text, Ctrl+C WILL NOT WORK!\e[0m\n"
    read -rp "Press Enter once you've added your key..."

    # Write SSH config
    cat > "$HOME/.ssh/config" << SSHEOF
Host lichen
    Hostname lichen.labs.eait.uq.edu.au
    User $UQ_USERNAME
    IdentityFile $HOME/.ssh/id_ed25519
    ForwardAgent yes

Host csse3010-gitea.zones.eait.uq.edu.au
    Hostname csse3010-gitea.zones.eait.uq.edu.au
    IdentityFile $HOME/.ssh/id_ed25519
    ProxyJump lichen
SSHEOF
    chmod 600 "$HOME/.ssh/config"
    printf "\e[32mSSH config written to ~/.ssh/config\e[0m\n"

    # Test SSH connection to lichen (retry until key is accepted)
    while true; do
      echo ""
      echo "Testing SSH connection to lichen..."
      if ${pkgs.openssh}/bin/ssh -i "$HOME/.ssh/id_ed25519" -o PasswordAuthentication=no -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$UQ_USERNAME@lichen.labs.eait.uq.edu.au" true &>/dev/null; then
        printf "\e[32mSSH connection to lichen successful!\e[0m\n"
        break
      fi
      echo ""
      printf "\e[31m\e[1mSSH connection to lichen failed.\e[0m\n"
      echo "Please ensure your public key is added to the EAIT SSH key portal."
      echo ""
      echo "If you have written the wrong student number, please close and reopen WSL!"
      echo ""
      echo "Your SSH public key:"
      echo "------------------------------------------------------------"
      cat "$HOME/.ssh/id_ed25519.pub"
      echo "------------------------------------------------------------"
      echo ""
      echo "Please copy this key into the portal located at:"
      printf "  \e[1mhttps://student.eait.uq.edu.au/accounts/sshkeys.ephp\e[0m\n"
      printf "\e[1mUse Ctrl+Shift+C to copy text, Ctrl+C WILL NOT WORK!\e[0m\n"
      read -rp "Press Enter to retry..."
    done

    # Clone student repo (retry until gitea key is accepted)
    REPO_URL="git@csse3010-gitea.zones.eait.uq.edu.au:$STUDENT_ID/repo.git"
    if [ -d "$HOME/csse3010/repo/.git" ]; then
      echo "Repo already cloned to ~/csse3010/repo, skipping."
    else
      rm -rf "$HOME/csse3010/repo"
      while true; do
        echo ""
        echo "Cloning your CSSE3010 repo..."
        if GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -o StrictHostKeyChecking=accept-new" \
           ${pkgs.git}/bin/git clone "$REPO_URL" "$HOME/csse3010/repo" &>/dev/null; then
          printf "\e[32m\e[1mRepo cloned successfully to ~/csse3010/repo!\e[0m\n"
          break
        fi
        echo ""
        printf "\e[31m\e[1mClone failed. Please ensure your SSH key is also added to the CSSE3010 Gitea portal.\e[0m"
        echo ""
        echo "Your SSH public key:"
        echo "------------------------------------------------------------"
        cat "$HOME/.ssh/id_ed25519.pub"
        echo "------------------------------------------------------------"
        echo ""
        echo "Please add this key into your Gitea SSH Key portal at:"
        printf "  \e[1mcsse3010-gitea.uqcloud.net/user/settings/keys\e[0m\n"
        printf "\e[1mUse Ctrl+Shift+C to copy text, Ctrl+C WILL NOT WORK!\e[0m\n"
        read -rp "Press Enter to retry..."
      done
    fi

    clear

    touch "$MARKER"
    sudo chmod 000 "$MARKER" 
    printf "\e[32m\e[1m"
    echo "======================================"
    echo " Setup complete! Welcome to CSSE3010! "
    echo "======================================"
    printf "\e[0m"
    sleep 2
  '';

  # MOTD — picks a random ASCII art block from the baked-in art file
  motdArtFile = ./art;
  motdScript = pkgs.writeShellScriptBin "motd" ''
    ART_FILE="${motdArtFile}"
    if [ ! -f "$ART_FILE" ]; then
      exit 0
    fi

    mapfile -t lines < "$ART_FILE"

    blocks=()
    current=""
    for line in "''${lines[@]}"; do
      if [ -z "$line" ]; then
        if [ -n "$current" ]; then
          blocks+=("$current")
          current=""
        fi
      else
        if [ -n "$current" ]; then
          current="''${current}"$'\n'"''${line}"
        else
          current="$line"
        fi
      fi
    done
    if [ -n "$current" ]; then
      blocks+=("$current")
    fi

    num_blocks=''${#blocks[@]}
    if [ "$num_blocks" -eq 0 ]; then
      exit 0
    fi

    index=$((RANDOM % num_blocks))
    art="''${blocks[$index]}"

    colours=(31 32 33 34 35 36 91 92 93 94 95 96)
    num_colours=''${#colours[@]}
    colour_index=$((RANDOM % num_colours))
    colour="''${colours[$colour_index]}"

    printf '\e[%sm%s\e[0m\n' "$colour" "$art"
  '';

  # Standalone git config helper (can be re-run anytime)
  configureInfoScript = pkgs.writeShellScriptBin "configure-info" ''
    set -euo pipefail

    if [ $# -ge 2 ]; then
      STUDENT_INPUT="''${1,,}"
      shift
      FULL_NAME="$*"
    else
      read -rp "Enter your UQ student ID (e.g. s48201356): " STUDENT_INPUT
      STUDENT_INPUT="''${STUDENT_INPUT,,}"
      read -rp "Enter your full name: " FULL_NAME
    fi

    if [[ ! "$STUDENT_INPUT" =~ ^s[0-9]{8}$ ]]; then
      echo "Error: Invalid format. Must be 's' followed by 8 digits (e.g. s48201356)."
      exit 1
    fi

    if [ -z "$FULL_NAME" ]; then
      echo "Error: Full name cannot be empty."
      exit 1
    fi

    STUDENT_ID="''${STUDENT_INPUT:1}"
    UQ_USERNAME="s''${STUDENT_ID:0:7}"
    EMAIL="$UQ_USERNAME@student.uq.edu.au"

    ${pkgs.git}/bin/git config --global user.name "$FULL_NAME"
    ${pkgs.git}/bin/git config --global user.email "$EMAIL"

    echo "Git configured:"
    echo "  user.name  = $FULL_NAME"
    echo "  user.email = $EMAIL"
  '';

  # Sourcelib clone bash script (RUNS AT BOOT UP BUT ENDS EARLY IF ALREADY EXECUTED)
  setupCsse3010Script = pkgs.writeShellScript "csse3010-setup-repo" ''
    set -euo pipefail
    MARKER="/home/${username}/.csse3010-setup-done"
    if [ -f "$MARKER" ]; then
      echo "sourcelib already cloned, skipping."
      exit 0
    fi

    mkdir -p "/home/${username}/csse3010"

    # Retry loop - WSL networking may take a moment on first boot
    MAX_RETRIES=10
    for i in $(seq 1 $MAX_RETRIES); do
      if ${pkgs.git}/bin/git clone \
           https://github.com/uqembeddedsys/sourcelib.git \
           "/home/${username}/csse3010/sourcelib"; then
        break
      fi
      echo "Clone attempt $i/$MAX_RETRIES failed, retrying in 5s..."
      sleep 5
    done

    if [ ! -d "/home/${username}/csse3010/sourcelib" ]; then
      echo "ERROR: Failed to clone sourcelib after $MAX_RETRIES attempts."
      exit 1
    fi

    chown -R ${username}:users "/home/${username}/csse3010"
    touch "$MARKER"
    chown ${username}:users "$MARKER"
    sudo chmod 000 "$MARKER" 
    echo "sourcelib successfully cloned to ~/csse3010/sourcelib!"
  '';

  jlinkDebuggerScript = pkgs.writeShellScriptBin "debug" ''
    (
      # Create temp log
      LOG=$(mktemp); 

      # Start the JLinkGDBServer, routing the output to the logfile
      # Backgrounds the process and notes the PID
      JLinkGDBServerCL -device STM32F429ZI -if SWD -speed 4000 -port 2331 -swoport 2332 -telnetport 2333 >"$LOG" 2>&1 & PID=$!;

      # Make sure the server has actually started
      grep -q "Listening on TCP/IP port 2331" <(tail -f "$LOG"); 

      # Run GDB and connect it to the JLinkGDB server automatically
      # This should be able to take in an argument or none, if none, just assumes the elf is in the current directory
      if ["$#" -ne "1"]; then
        arm-none-eabi-gdb "$1" -ex "target remote localhost:2331" -ex "monitor reset halt" -ex "load"; 
      else 
        arm-none-eabi-gdb main.elf -ex "target remote localhost:2331" -ex "monitor reset halt" -ex "load"; 
      fi

      # Kill the JLinkGDBServer if GDB exits
      kill $PID;

      # Remove the log file
      rm "$LOG";
    )
  '';

  # VS Code workspace configuration files (used by vscode-setup script)
  vscodeTasksJson = pkgs.writeText "vscode-tasks.json" ''
    {
        "version": "2.0.0",
        "tasks": [
            {
                "label": "make",
                "type": "shell",
                "command": "make"
            },
            {
                "label": "flash",
                "type": "shell",
                "dependsOn": "make",
                "command": "make flash",
                "group": {
                    "kind": "build",
                    "isDefault": true
                }
            },
            {
                "label": "clean",
                "type": "shell",
                "command": "make clean"
            }
        ]
    }
  '';

  vscodeLaunchJson = pkgs.writeText "vscode-launch.json" ''
    {
        "configurations": [
            {
                "name": "Debug",
                "cwd": "''${workspaceRoot}",
                "executable": "''${workspaceRoot}/main.elf",
                "preLaunchTask": "make",
                "request": "launch",
                "type": "cortex-debug",
                "servertype": "jlink",
                "device": "STM32F429ZI",
                "interface": "swd",
                "runToEntryPoint": "main",
                "rtos": "FreeRTOS",
                "svdFile": "''${env:SOURCELIB_ROOT}/tools/vscode/STM32F429.svd"
            }
        ]
    }
  '';

  vscodeSettingsJson = pkgs.writeText "vscode-settings.json" ''
    {
        // Reroute JLinkGDBServer to JLinkGDBServerCL
        "cortex-debug.JLinkGDBServerPath.linux": "JLinkGDBServerCL",

        "editor.rulers": [79],
        "editor.renderWhitespace": "all",
        "editor.tabSize": 4,
        "editor.insertSpaces": true
    }
  '';

  # TODO: Will compilerPath actually work..?
  vscodeCCppPropertiesJson = pkgs.writeText "vscode-c_cpp_properties.json" ''
    {
        "configurations": [
            {
                "name": "CSSE3010 Repo",
                "includePath": [
                    "''${workspaceFolder}/**",
                    "../mylib/**",
                    "''${env:SOURCELIB_ROOT}/components/boards/nucleo-f429zi/Inc/**",
                    "''${env:SOURCELIB_ROOT}/components/hal/STM32F4xx_HAL_Driver/Inc/**",
                    "''${env:SOURCELIB_ROOT}/components/hal/CMSIS/Include/**",
                    "''${env:SOURCELIB_ROOT}/components/os/FreeRTOS/include/**",
                    "''${env:SOURCELIB_ROOT}/components/os/FreeRTOS/portable/GCC/ARM_CM4F"
                ],
        "cStandard": "c99",
		"intelliSenseMode": "gcc-arm",
                "defines": [
                    // Define the flag for the microprocessor we're using.
                    "STM32F429xx",

                    // Define the integer types and ranges given that we're not
                    // using the system standard integer header. These may not be
                    // correct for the host operating system or the STM32, however
                    // it doesn't matter because we're not compiling with these
                    // values.
                    "__INT8_TYPE__=signed char",
                    "__INT16_TYPE__=signed short int",
                    "__INT32_TYPE__=signed long int",
                    "__INT64_TYPE__=signed long long int",
                    "__UINT8_TYPE__=unsigned char",
                    "__UINT16_TYPE__=unsigned short int",
                    "__UINT32_TYPE__=unsigned long int",
                    "__UINT64_TYPE__=unsigned long long int",
                    "__INT_LEAST8_TYPE__=signed char",
                    "__INT_LEAST16_TYPE__=signed short int",
                    "__INT_LEAST32_TYPE__=signed long int",
                    "__INT_LEAST64_TYPE__=signed long long int",
                    "__UINT_LEAST8_TYPE__=unsigned char",
                    "__UINT_LEAST16_TYPE__=unsigned short int",
                    "__UINT_LEAST32_TYPE__=unsigned long int",
                    "__UINT_LEAST64_TYPE__=unsigned long long int",
                    "__INT_FAST8_TYPE__=signed char",
                    "__INT_FAST16_TYPE__=signed short int",
                    "__INT_FAST32_TYPE__=signed long int",
                    "__INT_FAST64_TYPE__=signed long long int",
                    "__UINT_FAST8_TYPE__=unsigned char",
                    "__UINT_FAST16_TYPE__=unsigned short int",
                    "__UINT_FAST32_TYPE__=unsigned long int",
                    "__UINT_FAST64_TYPE__=unsigned long long int",
                    "__INTPTR_TYPE__=signed int",
                    "__UINTPTR_TYPE__=unsigned int",
                    "__INTMAX_TYPE__=signed long long int",
                    "__UINTMAX_TYPE__=unsigned long long int",
                    "__INT8_MAX__=127",
                    "__UINT8_MAX__=255",
                    "__INT16_MAX__=32767",
                    "__UINT16_MAX__=65535",
                    "__INT32_MAX__=2147483647L",
                    "__UINT32_MAX__=4294967295UL",
                    "__INT64_MAX__=9223372036854775807LL",
                    "__UINT64_MAX__=18446744073709551615ULL",
                    "__INT_LEAST8_MAX__=127",
                    "__UINT_LEAST8_MAX__=255",
                    "__INT_LEAST16_MAX__=32767",
                    "__UINT_LEAST16_MAX__=65535",
                    "__INT_LEAST32_MAX__=2147483647L",
                    "__UINT_LEAST32_MAX__=4294967295UL",
                    "__INT_LEAST64_MAX__=9223372036854775807LL",
                    "__UINT_LEAST64_MAX__=18446744073709551615ULL",
                    "__INT_FAST8_MAX__=127",
                    "__UINT_FAST8_MAX__=255",
                    "__INT_FAST16_MAX__=32767",
                    "__UINT_FAST16_MAX__=65535",
                    "__INT_FAST32_MAX__=2147483647L",
                    "__UINT_FAST32_MAX__=4294967295UL",
                    "__INT_FAST64_MAX__=9223372036854775807LL",
                    "__UINT_FAST64_MAX__=18446744073709551615ULL",
                    "__INTPTR_MAX__=2147483647L",
                    "__UINTPTR_MAX__=4294967295UL",
                    "__INTMAX_MAX__=9223372036854775807LL",
                    "__UINTMAX_MAX__=18446744073709551615ULL",
                    "__INT8_C(c)=c",
                    "__UINT8_C(c)=c",
                    "__INT16_C(c)=c",
                    "__UINT16_C(c)=c",
                    "__INT32_C(c)=c##L",
                    "__UINT32_C(c)=c##UL",
                    "__INT64_C(c)=c##LL",
                    "__UINT64_C(c)=c##ULL",
                    "__INTMAX_C(c)=c##LL",
                    "__UINTMAX_C(c)=c##ULL"
                ]
            }
        ],
        "version": 4
    }
  '';

  # TODO: Update the arm-none-eabi version in this - its probably wrong...
  clangdFile = pkgs.writeText "clangdFile" ''
    CompileFlags:
      Compiler: arm-none-eabi-gcc

      Add:
        - -I/usr/include/newlib
        - -I${pkgs.gcc-arm-embedded}/arm-none-eabi/include
        - -DUSE_FREERTOS_SYSTICK
        - -I/home/${username}/csse3010/sourcelib/components/os/FreeRTOS/include
        - -I/home/${username}/csse3010/sourcelib/components/os/FreeRTOS/portable/GCC/ARM_CM4F
        - -I/home/${username}/csse3010/sourcelib/components/os/FreeRTOS-Plus/Source/FreeRTOS-Plus-CLI
        - -DENABLE_DEBUG_UART
        - -Wmaybe-uninitialized
        - -Wextra
        - -std=gnu99
        - -Wsign-compare
        - -mlittle-endian
        - -mthumb
        - -mcpu=cortex-m4
        - -I/home/${username}/csse3010/sourcelib/components/hal/stm32/STM32_USB_Device_Library/Core/Inc
        - -I/home/${username}/csse3010/sourcelib/components/hal/stm32/STM32_USB_Device_Library/Class/CDC/Inc
        - -I/home/${username}/csse3010/sourcelib/components/boards/nucleo-f429zi/usb/vcp
        - -I/home/${username}/csse3010/sourcelib/components/boards/nucleo-f429zi/usb/hid
        - -I/home/${username}/csse3010/sourcelib/components/boards/nucleo-f429zi/usb
        - -I.
        - -I/home/${username}/csse3010/sourcelib/components/hal/stm32/STM32_USB_Device_Library/Class/HID/Inc
        - -I/home/${username}/csse3010/sourcelib/components/hal/CMSIS/Include
        - -I/home/${username}/csse3010/sourcelib/components/boards/nucleo-f429zi/Inc
        - -I/home/${username}/csse3010/sourcelib/components/hal/STM32F4xx_HAL_Driver/Inc
        - -I/home/${username}/csse3010/sourcelib/components/util
        - -DSTM32F429xx
        - -I/home/${username}/csse3010/repo/mylib
        - -I/home/${username}/csse3010/sourcelib/components/peripherals/nrf24l01plus

      Remove:
        - -mthumb-interwork 
  '';

  # Manual system update helper
  updateScript = pkgs.writeShellScriptBin "update" ''
    set -euo pipefail
    printf '\e[33mUpdating CSSE3010 system configuration...\e[0m\n'
    sudo nixos-rebuild switch --flake "${flakeUrl}" --refresh
    printf '\e[33mUpdating sourcelib library...\e[0m\n'
    ${pkgs.git}/bin/git -C /home/${username}/csse3010/sourcelib pull
    sudo nix-collect-garbage -d &>/dev/null
  '';

  # VS Code workspace config generator
  vscodeSetupScript = pkgs.writeShellScriptBin "vs-init" ''
    set -euo pipefail

    if [ $# -eq 0 ]; then
      set -- "."
    fi

    for dir in "$@"; do
      if [ ! -d "$dir" ]; then
        echo "Skipping '$dir': not a directory"
        continue
      fi

      VSCODE_DIR="$dir/.vscode"
      mkdir -p "$VSCODE_DIR"

      cp ${vscodeTasksJson} "$VSCODE_DIR/tasks.json"
      cp ${vscodeLaunchJson} "$VSCODE_DIR/launch.json"
      cp ${vscodeSettingsJson} "$VSCODE_DIR/settings.json"
      cp ${vscodeCCppPropertiesJson} "$VSCODE_DIR/c_cpp_properties.json"

      printf '\e[32mCreated .vscode config in %s\e[0m\n' "$(realpath "$dir")"
    done
  '';

    clangdInit = pkgs.writeShellScriptBin "clangd-init" ''
        set -euo pipefail

        cp ${clangdFile} "/home/${username}/csse3010/.clangd"
    '';
in
{
  ###################################
  #       Base System Install       #
  ###################################
  system.stateVersion = "25.05";

  #############################
  #  Auto-update from remote  #
  #############################

 # system.autoUpgrade = {
 #   enable = true;
 #   flake = flakeUrl;
 #   dates = "daily";
 #   allowReboot = false;
 # };

  #################################
  #   WSL Specific Properties!!   #
  #################################

  wsl = {
    enable = true;
    defaultUser = username;
    usbip.enable = true;
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  ###################################
  #    Let JLink work properly!!    #
  ###################################

  nixpkgs.config = {
    allowUnfree = true;
    segger-jlink.acceptLicense = true;
    # Use a predicate so this survives J-Link version bumps across
    # nixpkgs updates (the insecure package name includes the version).
    allowInsecurePredicate = pkg:
      lib.hasPrefix "segger-jlink" (lib.getName pkg);
  };

  ##################################
  #  System Packages Declaration   #
  ##################################

  environment.systemPackages = with pkgs; [
    # Main ones
    screen
    gcc-arm-embedded
    segger-jlink
    (python3.withPackages (ps: [ ps.pylink-square ]))
    git

    # Student's can pick their poison
    vim
    neovim

    # Other maybe helpful stuff
    gnumake
    openssh
    wget
    curl
    usbutils
    minicom

    # LSP stuff students can play with if they want
    clang-tools
    bear

    # First-time setup scripts
    firstTimeSetupScript
    configureInfoScript

    # Available scripts to the user
    jlinkDebuggerScript
    vscodeSetupScript
    updateScript
    clangdInit

    # Runs every time user logs in
    motdScript
  ];

  ############################
  #   VS Code WSL Support!   #
  ############################

  # nix-ld provides a dynamic linker at the FHS-expected path so the
  # VS Code Server's bundled Node.js binary (and other downloaded
  # dynamically-linked binaries) can execute on NixOS.
  programs.nix-ld.enable = true;

  ######################################
  # Auto-trigger first-time user setup #
  ######################################

  # Runs in the user's interactive terminal (not a background service)
  # so the student can respond to prompts. Checks marker file so it
  # only fires once; prerequisites gate ensure ssh key + sourcelib exist.
  environment.interactiveShellInit = ''
    if [ ! -f "$HOME/.csse3010-user-setup-done" ] && [ "$USER" = "${username}" ]; then
      if [ ! -f "$HOME/.ssh/id_ed25519" ] || [ ! -f "$HOME/.csse3010-setup-done" ]; then
        printf "Waiting for first-boot services to complete..."
        _timeout=120
        _elapsed=0
        while [ ! -f "$HOME/.ssh/id_ed25519" ] || [ ! -f "$HOME/.csse3010-setup-done" ]; do
          if [ "$_elapsed" -ge "$_timeout" ]; then
            echo ""
            echo "Timed out. Please log out and back in, or check: systemctl status csse3010-generate-ssh-keys csse3010-setup-repo"
            break
          fi
          printf "."
          sleep 2
          _elapsed=$((_elapsed + 2))
        done
        echo ""
      fi
      if [ -f "$HOME/.ssh/id_ed25519" ] && [ -f "$HOME/.csse3010-setup-done" ]; then
        csse3010-first-setup
      fi
    fi
    clear
    motd
  '';

  ###########################
  #  Environment Variables  #
  ###########################

  environment.sessionVariables = {
    SOURCELIB_ROOT = "/home/${username}/csse3010/sourcelib";
  };

  # PATH & LD_LIBRARY_PATH additions that the sourcelib shellHook sets.
  environment.shellInit = ''
    if [ -d "$HOME/csse3010/sourcelib/tools" ]; then
      export PATH="$HOME/csse3010/sourcelib/tools:$PATH"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    export LD_LIBRARY_PATH="${pkgs.segger-jlink}/bin''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  ###########################
  #       User Groups       #
  ###########################

  users.users.${username} = {
    extraGroups = [ "wheel" "dialout" "plugdev" ];
  };

  users.groups.plugdev = {};

  ###########################
  #  UDev rules for serial  #
  ###########################

  services.udev.extraRules = ''
    # Generic serial (ttyACM*, ttyUSB*)
    SUBSYSTEM=="tty", KERNEL=="ttyACM[0-9]*", MODE="0660", GROUP="dialout"
    SUBSYSTEM=="tty", KERNEL=="ttyUSB[0-9]*", MODE="0660", GROUP="dialout"

    # SEGGER J-Link
    SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666", GROUP="plugdev"

    # ST-Link v2 and v2.1
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="374b", MODE="0666", GROUP="plugdev"
  '';

  ############################
  # Systemd script execution #
  ############################

  systemd.services.csse3010-generate-ssh-keys = {
    description = "Generate SSH keys";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = generateSshKeysScript;
      RemainAfterExit = true;
    };
    unitConfig.ConditionPathExists = "!/home/${username}/.ssh/id_ed25519";
  };
  
  systemd.user.services.csse3010-autoupdate = {
    description = "Auto-update and sourcelib reset";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [  pkgs.nix pkgs.git ];
    environment = {
      HOME = "/home/${username}";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "csse3010-autoupdate" ''
        set -euo pipefail
        sudo nixos-rebuild switch --flake "${flakeUrl}" --refresh || true
        ${pkgs.git}/bin/git config --global --add safe.directory /home/${username}/csse3010/sourcelib
        ${pkgs.git}/bin/git -C /home/${username}/csse3010/sourcelib fetch --all
        ${pkgs.git}/bin/git -C /home/${username}/csse3010/sourcelib reset --hard origin/main
        sudo nix-collect-garbage -d || true
      '';
      RemainAfterExit = true;
    };
  };

  systemd.services.csse3010-setup-repo = {
    description = "Clone CSSE3010 sourcelib repository";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = setupCsse3010Script;
      RemainAfterExit = true;
    };
    unitConfig.ConditionPathExists = "!/home/${username}/.csse3010-setup-done";
  };
}
