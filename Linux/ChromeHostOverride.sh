#!/usr/bin/env bash

# ChromeHostOverride - Linux
# Persistent hostname mappings and isolated Chrome sessions.

set -u

APP_NAME="ChromeHostOverride"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/chromehostoverride"
CONFIG_FILE="$CONFIG_DIR/mappings.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"

# ------------------------------------------------------------
# Dependencies and browser detection
# ------------------------------------------------------------

for DEP in zenity python3; do
    if ! command -v "$DEP" >/dev/null 2>&1; then
        echo "Missing dependency: $DEP"
        exit 1
    fi
done

CHROME=$(command -v google-chrome-stable ||
         command -v google-chrome ||
         command -v chromium ||
         command -v chromium-browser || true)

if [[ -z "$CHROME" ]]; then
    zenity --error --text="Google Chrome or Chromium was not found."
    exit 1
fi

mkdir -p "$CONFIG_DIR" "$CACHE_DIR" || exit 1

# ------------------------------------------------------------
# Persistent mapping database
# ------------------------------------------------------------

declare -a FQDNS=()
declare -a IPS=()
declare -a SESSION_FQDNS=()
declare -a SESSION_IPS=()

load_mappings() {
    FQDNS=()
    IPS=()

    [[ -f "$CONFIG_FILE" ]] || return 0

    while IFS=$'\t' read -r fqdn ip; do
        [[ -z "$fqdn" || -z "$ip" ]] && continue
        FQDNS+=("$fqdn")
        IPS+=("$ip")
    done < <(
        python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for item in data.get("mappings", []):
    print(item["fqdn"] + "\t" + item["ip"])
' "$CONFIG_FILE" 2>/dev/null
    )
}

save_mappings() {
    local input=""

    for i in "${!FQDNS[@]}"; do
        input+="${FQDNS[$i]}"$'\t'"${IPS[$i]}"$'\n'
    done

    if ! printf '%s' "$input" | python3 -c '
import json, sys, os

path = os.environ["CHROMEHOST_CONFIG"]

mappings = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    fqdn, ip = line.split("\t", 1)
    mappings.append({"fqdn": fqdn, "ip": ip})

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"mappings": mappings}, f, indent=2)
    f.write("\n")

os.replace(tmp, path)
'; then
        zenity --error --text="Could not save the mapping database."
        return 1
    fi
}

export CHROMEHOST_CONFIG="$CONFIG_FILE"

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

validate_mapping() {
    python3 - "$1" "$2" <<'PY'
import sys
import re
import ipaddress

fqdn, address = sys.argv[1:3]
fqdn = fqdn.rstrip(".")

valid = (
    len(fqdn) <= 253
    and all(
        re.fullmatch(
            r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?',
            label
        )
        for label in fqdn.split(".")
    )
)

try:
    ipaddress.ip_address(address)
except ValueError:
    valid = False

sys.exit(0 if valid else 1)
PY
}

# ------------------------------------------------------------
# Add mapping
# ------------------------------------------------------------

add_mapping() {
    local fqdn ip i

    fqdn=$(zenity --entry \
        --title="$APP_NAME - Add mapping" \
        --text="Enter the FQDN / hostname:")

    [[ $? -ne 0 ]] && return

    ip=$(zenity --entry \
        --title="$APP_NAME - Add mapping" \
        --text="Enter the corresponding IP address:")

    [[ $? -ne 0 ]] && return

    if ! validate_mapping "$fqdn" "$ip"; then
        zenity --error --text="Invalid FQDN or IP address."
        return
    fi

    for i in "${!FQDNS[@]}"; do
        if [[ "${FQDNS[$i],,}" == "${fqdn,,}" ]]; then
            zenity --error --text="This hostname already exists."
            return
        fi
    done

    FQDNS+=("$fqdn")
    IPS+=("$ip")

    save_mappings
}

# ------------------------------------------------------------
# Select a saved mapping for editing or deletion
# ------------------------------------------------------------

select_mapping() {
    local -n result=$1
    result=()

    local rows=()
    local i

    for i in "${!FQDNS[@]}"; do
        rows+=("$((i+1))" "${FQDNS[$i]}" "${IPS[$i]}")
    done

    [[ ${#FQDNS[@]} -eq 0 ]] && {
        zenity --info --text="No saved mappings."
        return 1
    }

    # Do not name this variable "selected": the caller may use that
    # name for the array passed through the nameref above. Bash uses
    # dynamic scoping, so reusing the name would shadow the caller's array.
    local selection
    selection=$(zenity --list \
        --title="$APP_NAME - Select mapping" \
        --width=650 --height=400 \
        --column="ID" --column="FQDN" --column="IP address" \
        --print-column=1 \
        "${rows[@]}")

    [[ $? -ne 0 || -z "$selection" ]] && return 1

    result=("$((selection-1))")
}

edit_mapping() {
    local selected=()
    select_mapping selected || return

    local i=${selected[0]}
    local fqdn ip

    fqdn=$(zenity --entry \
        --title="$APP_NAME - Edit mapping" \
        --text="FQDN:" --entry-text="${FQDNS[$i]}") || return

    ip=$(zenity --entry \
        --title="$APP_NAME - Edit mapping" \
        --text="IP address:" --entry-text="${IPS[$i]}") || return

    if ! validate_mapping "$fqdn" "$ip"; then
        zenity --error --text="Invalid FQDN or IP address."
        return
    fi

    local j
    for j in "${!FQDNS[@]}"; do
        if [[ $j -ne $i && "${FQDNS[$j],,}" == "${fqdn,,}" ]]; then
            zenity --error --text="This hostname already exists."
            return
        fi
    done

    FQDNS[$i]="$fqdn"
    IPS[$i]="$ip"

    save_mappings
}

delete_mapping() {
    [[ ${#FQDNS[@]} -eq 0 ]] && {
        zenity --info --text="No saved mappings."
        return
    }

    local rows=()
    local i

    for i in "${!FQDNS[@]}"; do
        rows+=("$((i+1))" "${FQDNS[$i]}" "${IPS[$i]}")
    done

    local selected
    selected=$(zenity --list --multiple \
        --title="$APP_NAME - Delete mappings" \
        --width=650 --height=400 \
        --text="Select one or more mappings to delete:" \
        --column="ID" --column="FQDN" --column="IP address" \
        --print-column=1 \
        --separator="|" \
        "${rows[@]}")

    [[ $? -ne 0 || -z "$selected" ]] && return

    if ! zenity --question \
        --title="$APP_NAME - Confirm deletion" \
        --text="Delete the selected mappings?"
    then
        return
    fi

    local -a indices=()
    IFS='|' read -r -a indices <<< "$selected"

    for ((i=${#indices[@]}-1; i>=0; i--)); do
        local index=$((${indices[$i]}-1))
        unset "FQDNS[$index]" "IPS[$index]"
    done

    FQDNS=("${FQDNS[@]}")
    IPS=("${IPS[@]}")

    save_mappings
}

# ------------------------------------------------------------
# Select mappings for this session
# ------------------------------------------------------------

select_session_mappings() {
    SESSION_FQDNS=()
    SESSION_IPS=()

    if [[ ${#FQDNS[@]} -eq 0 ]]; then
        zenity --info --text="No mappings available. Add some first."
        return 1
    fi

    local rows=()
    local i

    for i in "${!FQDNS[@]}"; do
        rows+=("FALSE" "$((i+1))" "${FQDNS[$i]}" "${IPS[$i]}")
    done

    local selected
    selected=$(zenity --list --checklist \
        --title="$APP_NAME - Session mappings" \
        --width=750 --height=450 \
        --text="Select the mappings to activate in this Chrome session:" \
        --column="Use" --column="ID" --column="FQDN" --column="IP address" \
        --print-column=2 \
        --separator="|" \
        "${rows[@]}")

    [[ $? -ne 0 ]] && return 1
    [[ -z "$selected" ]] && {
        zenity --error --text="Select at least one mapping."
        return 1
    }

    local -a indices=()
    IFS='|' read -r -a indices <<< "$selected"

    for idx in "${indices[@]}"; do
        local index=$((idx - 1))
        if [[ -n "${FQDNS[$index]:-}" && -n "${IPS[$index]:-}" ]]; then
            SESSION_FQDNS+=("${FQDNS[$index]}")
            SESSION_IPS+=("${IPS[$index]}")
        fi
    done

    [[ ${#SESSION_FQDNS[@]} -gt 0 ]]
}

# ------------------------------------------------------------
# Launch Chrome
# ------------------------------------------------------------

launch_chrome() {
    select_session_mappings || return

    local rules=()
    local i ip

    for i in "${!SESSION_FQDNS[@]}"; do
        ip=${SESSION_IPS[$i]}

        if [[ "$ip" == *:* ]]; then
            ip="[$ip]"
        fi

        rules+=("MAP ${SESSION_FQDNS[$i]} $ip")
    done

    if ! zenity --question \
        --title="$APP_NAME - Confirm launch" \
        --width=500 \
        --text="Chrome will launch with these mappings:\n\n$(printf '%s\n' "${rules[@]}")\n\nProceed?"
    then
        return
    fi

    shopt -s nullglob
    local old_profiles=("$CACHE_DIR"/IsolatedChrome_*)
    shopt -u nullglob

    local previous=()
    local profile

    for profile in "${old_profiles[@]}"; do
        if [[ -d "$profile" && ! -L "$profile" ]]; then
            previous+=("$profile")
        fi
    done

    if [[ ${#previous[@]} -gt 0 ]]; then
        if zenity --question \
            --title="Previous profiles found" \
            --width=450 \
            --text="Found ${#previous[@]} previous isolated Chrome profile(s).\n\nWould you like to delete them before proceeding?\n\nMake sure their Chrome sessions are closed."
        then
            for profile in "${previous[@]}"; do
                if ! rm -rf -- "$profile"; then
                    zenity --error --text="Could not remove $profile"
                    return
                fi
            done
        fi
    fi

    local timestamp user_data_dir

    timestamp=$(date '+%Y%m%d_%H%M%S_%N')
    user_data_dir="$CACHE_DIR/IsolatedChrome_${timestamp}"

    local host_rules
    host_rules=$(IFS=', '; echo "${rules[*]}")

    "$CHROME" \
        --incognito \
        --test-type \
        --user-data-dir="$user_data_dir" \
        --host-resolver-rules="$host_rules" &
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

load_mappings

while true; do
    ACTION=$(zenity --list \
        --title="$APP_NAME" \
        --width=420 --height=330 \
        --text="Saved hostname mappings: ${#FQDNS[@]}" \
        --column="Action" \
        "Launch Chrome session" \
        "Add mapping" \
        "Edit mapping" \
        "Delete mapping" \
        "Exit")

    [[ $? -ne 0 || "$ACTION" == "Exit" ]] && exit 0

    case "$ACTION" in
        "Launch Chrome session")
            launch_chrome
            ;;
        "Add mapping")
            add_mapping
            ;;
        "Edit mapping")
            edit_mapping
            ;;
        "Delete mapping")
            delete_mapping
            ;;
    esac
done
