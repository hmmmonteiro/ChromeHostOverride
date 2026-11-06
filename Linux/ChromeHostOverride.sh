#!/usr/bin/env bash
#
# ChromeHostOverride - Linux
# Persistent hostname mappings and isolated Chrome sessions.

set -u

# ------------------------------------------------------------
# Bash version check (namerefs require bash 4.3+)
# ------------------------------------------------------------
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "Bash 4.3 or newer is required." >&2
    exit 1
fi

APP_NAME="ChromeHostOverride"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/chromehostoverride"
CONFIG_FILE="$CONFIG_DIR/mappings.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"

# Must be exported before save_mappings is ever invoked.
export CHROMEHOST_CONFIG="$CONFIG_FILE"

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
#
# Mappings are stored as three parallel arrays:
#   FQDNS[i]  hostname
#   IPS[i]    IP address
#   USE[i]    "1" if checked for the session, "0" otherwise
# ------------------------------------------------------------

declare -a FQDNS=()
declare -a IPS=()
declare -a USE=()

declare -a SESSION_FQDNS=()
declare -a SESSION_IPS=()

load_mappings() {
    FQDNS=()
    IPS=()
    USE=()

    [[ -f "$CONFIG_FILE" ]] || return 0

    local line fqdn ip use
    while IFS=$'\t' read -r fqdn ip use; do
        [[ -z "$fqdn" || -z "$ip" ]] && continue
        FQDNS+=("$fqdn")
        IPS+=("$ip")
        USE+=("${use:-0}")
    done < <(
        python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for item in data.get("mappings", []):
    use = "1" if item.get("use") else "0"
    print(item["fqdn"] + "\t" + item["ip"] + "\t" + use)
' "$CONFIG_FILE" 2>/dev/null
    )
}

save_mappings() {
    local input=""
    local i

    for i in "${!FQDNS[@]}"; do
        input+="${FQDNS[$i]}"$'\t'"${IPS[$i]}"$'\t'"${USE[$i]:-0}"$'\n'
    done

    if ! printf '%s' "$input" | python3 -c '
import json, sys, os

path = os.environ["CHROMEHOST_CONFIG"]

mappings = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("\t", 2)
    if len(parts) < 2:
        continue
    fqdn, ip = parts[0], parts[1]
    use = (parts[2] == "1") if len(parts) > 2 else False
    mappings.append({"fqdn": fqdn, "ip": ip, "use": use})

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

# ------------------------------------------------------------
# Validation (DNS RFC 1035 / RFC 1123)
#
# Mirrors the PowerShell Test-Mapping function:
#   * Total length 1-253 chars.
#   * Labels 1-63 chars, dot-separated.
#   * Each label starts and ends with a letter or digit.
#   * Label charset: A-Z, a-z, 0-9, hyphen. Underscores rejected.
#   * A single trailing dot is stripped (FQDN form).
# ------------------------------------------------------------

validate_mapping() {
    python3 - "$1" "$2" <<'PY'
import sys
import re
import ipaddress

fqdn, address = sys.argv[1:3]

# Strip exactly one trailing dot (FQDN form).
if fqdn.endswith("."):
    fqdn = fqdn[:-1]

label_re = re.compile(r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?')

valid = True
if not fqdn or len(fqdn) > 253:
    valid = False
else:
    for label in fqdn.split("."):
        if not label_re.fullmatch(label):
            valid = False
            break

if valid:
    try:
        ipaddress.ip_address(address)
    except ValueError:
        valid = False

sys.exit(0 if valid else 1)
PY
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

# Build the "id<TAB>fqdn<TAB>ip" triples used by zenity lists.
build_rows() {
    local -n _out=$1
    _out=()
    local i
    for i in "${!FQDNS[@]}"; do
        _out+=("$((i+1))" "${FQDNS[$i]}" "${IPS[$i]}")
    done
}

# Case-insensitive duplicate check. $1 = candidate, $2 = index to skip (-1 = none).
is_duplicate_hostname() {
    local candidate="${1,,}"
    candidate="${candidate%.}"
    local skip="$2"
    local i
    for i in "${!FQDNS[@]}"; do
        [[ "$i" -eq "$skip" ]] && continue
        local existing="${FQDNS[$i],,}"
        existing="${existing%.}"
        [[ "$existing" == "$candidate" ]] && return 0
    done
    return 1
}

# ------------------------------------------------------------
# Add mapping
# ------------------------------------------------------------

add_mapping() {
    local fqdn ip

    fqdn=$(zenity --entry \
        --title="$APP_NAME - Add mapping" \
        --text="Enter the FQDN / hostname:") || return

    ip=$(zenity --entry \
        --title="$APP_NAME - Add mapping" \
        --text="Enter the corresponding IP address:") || return

    if ! validate_mapping "$fqdn" "$ip"; then
        zenity --error --text="Invalid FQDN or IP address."
        return
    fi

    # Normalise a trailing dot before storing.
    fqdn="${fqdn%.}"

    if is_duplicate_hostname "$fqdn" -1; then
        zenity --error --text="This hostname already exists."
        return
    fi

    FQDNS+=("$fqdn")
    IPS+=("$ip")
    USE+=("1")

    save_mappings
}

# ------------------------------------------------------------
# Select a saved mapping for editing or deletion
# ------------------------------------------------------------

select_mapping() {
    local -n result=$1
    result=()

    if [[ ${#FQDNS[@]} -eq 0 ]]; then
        zenity --info --text="No saved mappings."
        return 1
    fi

    local rows=()
    build_rows rows

    local selection
    selection=$(zenity --list \
        --title="$APP_NAME - Select mapping" \
        --width=650 --height=400 \
        --column="ID" --column="FQDN" --column="IP address" \
        --print-column=1 \
        "${rows[@]}") || return 1

    [[ -z "$selection" ]] && return 1

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

    fqdn="${fqdn%.}"

    if is_duplicate_hostname "$fqdn" "$i"; then
        zenity --error --text="This hostname already exists."
        return
    fi

    FQDNS[$i]="$fqdn"
    IPS[$i]="$ip"

    save_mappings
}

delete_mapping() {
    if [[ ${#FQDNS[@]} -eq 0 ]]; then
        zenity --info --text="No saved mappings."
        return
    fi

    local rows=()
    build_rows rows

    local selected
    selected=$(zenity --list --multiple \
        --title="$APP_NAME - Delete mappings" \
        --width=650 --height=400 \
        --text="Select one or more mappings to delete:" \
        --column="ID" --column="FQDN" --column="IP address" \
        --print-column=1 \
        --separator="|" \
        "${rows[@]}") || return

    [[ -z "$selected" ]] && return

    if ! zenity --question \
        --title="$APP_NAME - Confirm deletion" \
        --text="Delete the selected mappings?"
    then
        return
    fi

    local -a indices=()
    IFS='|' read -r -a indices <<< "$selected"

    # Iterate highest-to-lowest so unsetting does not shift remaining indices.
    local k
    for ((k=${#indices[@]}-1; k>=0; k--)); do
        local index=$((indices[k] - 1))
        unset "FQDNS[$index]" "IPS[$index]" "USE[$index]"
    done

    FQDNS=("${FQDNS[@]}")
    IPS=("${IPS[@]}")
    USE=("${USE[@]}")

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
        local checked="FALSE"
        [[ "${USE[$i]:-0}" == "1" ]] && checked="TRUE"
        rows+=("$checked" "$((i+1))" "${FQDNS[$i]}" "${IPS[$i]}")
    done

    local selected
    selected=$(zenity --list --checklist \
        --title="$APP_NAME - Session mappings" \
        --width=750 --height=450 \
        --text="Select the mappings to activate in this Chrome session:" \
        --column="Use" --column="ID" --column="FQDN" --column="IP address" \
        --print-column=2 \
        --separator="|" \
        "${rows[@]}") || return 1

    if [[ -z "$selected" ]]; then
        zenity --error --text="Select at least one mapping."
        return 1
    fi

    # Reset the persisted "use" flags.
    for i in "${!USE[@]}"; do USE[$i]="0"; done

    local -a indices=()
    IFS='|' read -r -a indices <<< "$selected"

    local idx index
    for idx in "${indices[@]}"; do
        index=$((idx - 1))
        if [[ -n "${FQDNS[$index]:-}" && -n "${IPS[$index]:-}" ]]; then
            SESSION_FQDNS+=("${FQDNS[$index]}")
            SESSION_IPS+=("${IPS[$index]}")
            USE[$index]="1"
        fi
    done

    [[ ${#SESSION_FQDNS[@]} -gt 0 ]]
}

# ------------------------------------------------------------
# Launch Chrome
# ------------------------------------------------------------

launch_chrome() {
    select_session_mappings || return

    # Persist the checkbox state so it survives a restart.
    save_mappings

    local rules=()
    local i ip

    for i in "${!SESSION_FQDNS[@]}"; do
        ip=${SESSION_IPS[$i]}

        # Chrome expects IPv6 addresses in [brackets] inside resolver rules.
        if [[ "$ip" == *:* ]]; then
            ip="[$ip]"
        fi

        rules+=("MAP ${SESSION_FQDNS[$i]} $ip")
    done

    local rule_text
    rule_text=$(printf '%s\n' "${rules[@]}")

    if ! zenity --question \
        --no-markup \
        --title="$APP_NAME - Confirm launch" \
        --width=500 \
        --text="Chrome will launch with these mappings:

$rule_text

Proceed?"
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
            --no-markup \
            --title="Previous profiles found" \
            --width=450 \
            --text="Found ${#previous[@]} previous isolated Chrome profile(s).

Delete them before proceeding?

(Make sure their Chrome sessions are closed.)"
        then
            for profile in "${previous[@]}"; do
                if ! rm -rf -- "$profile"; then
                    # Non-fatal: log and continue.
                    echo "Warning: could not remove '$profile'" >&2
                fi
            done
        fi
    fi

    local timestamp user_data_dir

    # GNU date supports %N; fall back to a random suffix elsewhere.
    if date '+%N' 2>/dev/null | grep -qE '^[0-9]+$'; then
        timestamp=$(date '+%Y%m%d_%H%M%S_%N')
    else
        timestamp=$(date '+%Y%m%d_%H%M%S')_$RANDOM
    fi

    user_data_dir="$CACHE_DIR/IsolatedChrome_${timestamp}"

    local host_rules
    host_rules=$(IFS=', '; echo "${rules[*]}")

    "$CHROME" \
        --incognito \
        --test-type \
        --no-first-run \
        --no-default-browser-check \
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
        "Exit") || exit 0

    case "$ACTION" in
        "Launch Chrome session") launch_chrome ;;
        "Add mapping")           add_mapping ;;
        "Edit mapping")          edit_mapping ;;
        "Delete mapping")        delete_mapping ;;
        "Exit"|"")               exit 0 ;;
    esac
done