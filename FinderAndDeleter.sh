#!/bin/bash
## Version 2.1.0-1
# Author: Tymofii Kravtsov (snow-penguin8)
# THANKS FOR HELP Andy Crowd i pick a little piece of code from his repository
# Tested in Arch Linux, NIRI.. dont know is does this matter?
# Search for Broken Exec in *.desktop plus search broken desktops of Steam flatpak and others
#
# CHANGES vs 2.1.0-1:
#  - added: basic flatpak awareness (Exec=flatpak run <app-id> ...) so
#    flatpak apps aren't misjudged just because `flatpak` exists.
 
set -o pipefail
 


# searching every "steamapps" directory across all Steam library folders
# (default install + any extra libraries regustered in "libraryfolders.vdf" with my external drive its worked
get_steam_steamapps_dirs() {
    local bases=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    )
    local dirs=()
    local base vdf extra
    for base in "${bases[@]}"; do
        [[ -d "$base/steamapps" ]] && dirs+=("$base/steamapps")
        vdf="$base/steamapps/libraryfolders.vdf"
        if [[ -f "$vdf" ]]; then
            while IFS= read -r extra; do
                [[ -n "$extra" && -d "$extra/steamapps" ]] && dirs+=("$extra/steamapps")
            done < <(grep -oP '"path"\s*"\K[^"]+' "$vdf" 2>/dev/null)
        fi
    done
    printf '%s\n' "${dirs[@]}" | sort -u
}
 
# $1 = Steam App ID -> returns 0 if that game's manifest exists anywhere
steam_game_installed() {
    local appid="$1" dir
    while IFS= read -r dir; do
        [[ -f "$dir/appmanifest_${appid}.acf" ]] && return 0
    done < <(get_steam_steamapps_dirs)
    return 1
}
 
# $1 = raw Exec= value -> echoes the real command to test (quote-aware,
# skips env/VAR=val wrappers). No eval is used, so it's safe even if the
# Exec line contains $() or backticks as plain text
# 
resolve_exec_cmd() {
    local exec_line="$1"
    local tokens=()
    while IFS= read -r tok; do
        tokens+=("$tok")
    done < <(printf '%s\n' "$exec_line" | xargs -n1 2>/dev/null)
 
    local i=0
    # skip a leading "env" wrapper and any VAR=val assignments
    if [[ "${tokens[0]}" == "env" ]]; then
        i=1
        while [[ "${tokens[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; do
            ((i++))
        done
    fi
    echo "${tokens[$i]}"
}
 
# $1 = command token -> returns 0 if it actually exists/is runnable
cmd_exists() {
    local cmd="$1"
    [[ -z "$cmd" ]] && return 1
    if [[ "$cmd" == /* ]]; then
        [[ -x "$cmd" ]] && return 0 || return 1
    fi
    command -v "$cmd" &>/dev/null
}
 
# # # # # # # # # # # # # # # # # # 
# #  buildingg paths to scann   # #  
# # # # # # # # # # # # # # # # # # 
declare -a DskPath
declare -a MaxDepth
 
if [ "$1" ]; then
    idx=0
    for fdPath in "$@"; do
        if [[ -d "$fdPath" || -f "$fdPath" ]]; then
            DskPath[idx]="$fdPath"
            ((idx++))
        else
            echo "Wrong path: $fdPath"
            exit 1
        fi
    done
else
    DskPath[0]="/usr/share/applications/"
    DskPath[1]="$HOME/.local/share/applications/"
    DskPath[2]="/usr/local/share/applications"
    DskPath[3]="/etc/xdg/autostart/"
    DskPath[4]="$HOME/.config/autostart/"
    DskPath[5]="$XDG_CONFIG_DIRS/autostart/"
    DskPath[6]="$XDG_CONFIG_HOME/autostart/"
    DskPath[7]="/usr/share/gnome/autostart/"
    #### Search with no subdirs
    MaxDepth[8]="-maxdepth 1"
    DskPath[8]="$HOME/Desktop"
    ####
    DskPath[9]="/usr/etc/xdg/autostart/"
    DskPath[10]="/usr/share/mimelnk/application/"
    DskPath[11]="/usr/share/mimelnk/chemical/"
    DskPath[12]="/usr/lib/libreoffice/share/xdg/"
    DskPath[13]="/usr/share/xsessions/"
    DskPath[14]="/usr/share/apps/kdm/sessions/"
    DskPath[15]="/usr/share/gdm/greeter/autostart/"
    DskPath[16]="/usr/share/wayland-sessions/"
    DskPath[17]="/usr/share/apps/kdm/programs/"
    DskPath[18]="/usr/share/mate/wm-properties/"
fi

# # # # # # # # # # # # # # # # #
# # # SCANNING A FILE HERE  # # #
# # # # # # # # # # # # # # # # #

for i in "${!DskPath[@]}"; do
    fdPath="${DskPath[$i]}"
    maxDepth="${MaxDepth[$i]}"
    [[ -z "$fdPath" ]] && continue
    if [[ -d "$fdPath" || -f "$fdPath" ]]; then
        find "$fdPath" $maxDepth -type f -iname '*.desktop' -print0 2>/dev/null |
        while IFS= read -r -d '' file; do
            exec_line=$(grep -m 1 '^Exec=' "$file" | cut -d'=' -f2-)
            [[ -z "$exec_line" ]] && continue
 
            is_broken=0
            reason=""
 
            if [[ "$exec_line" =~ steam://rungameid/([0-9]+) ]]; then
                appid="${BASH_REMATCH[1]}"
                if ! command -v steam &>/dev/null && ! command -v steam.sh &>/dev/null; then
                    is_broken=1
                    reason="Steam not found"
                elif ! steam_game_installed "$appid"; then
                    is_broken=1
                    reason="steam game - (AppID $appid) cannon found"
                fi
            else
                cmd=$(resolve_exec_cmd "$exec_line")
 
                if [[ "$cmd" == "flatpak" ]]; then
                    appid=$(printf '%s\n' "$exec_line" | xargs -n1 2>/dev/null |
                             awk '/^run$/{f=1;next} f && $0 !~ /^--/ {print; exit}')
                    if ! command -v flatpak &>/dev/null; then
                        is_broken=1
                        reason="flatpak not found"
                    elif [[ -n "$appid" ]] && ! flatpak info "$appid" &>/dev/null; then
                        is_broken=1
                        reason="Flatpak-app $appid cannon found"
                    fi
                else
                    if ! cmd_exists "$cmd"; then
                        is_broken=1
                        reason="bin - '$cmd' cannon found"
                    fi
                fi
            fi
 
            if [ "$is_broken" -eq 1 ]; then
                echo -e "\n\033[1;31m[Broken desktop]:\033[0m $file ($exec_line)"
                echo -e "  \033[0;33mReason:\033[0m $reason"
                read -p "delete?? (y/N): " choice < /dev/tty
                if [[ "$choice" =~ ^[YyДд]$ ]]; then
                    rm -f "$file" && echo "Deleted."
                else
                    echo "skiped."
                fi
            fi
        done
    fi
done

# i love my wife btw
