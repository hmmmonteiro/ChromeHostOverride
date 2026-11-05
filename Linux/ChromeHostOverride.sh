
#!/usr/bin/env bash

# ChromeHostOverride
# Launch Chrome/Chromium with custom hostname-to-IP mappings
# and a fresh, isolated browser profile.

# Check dependencies
for DEP in zenity python3; do
    if ! command -v "$DEP" >/dev/null 2>&1; then
	echo "Missing dependency: $DEP"
	exit 1
    fi
done

# Find Chrome / Chromium
CHROME=$(command -v google-chrome-stable ||
	 command -v google-chrome ||
	 command -v chromium ||
	 command -v chromium-browser)

if [[ -z "$CHROME" ]]; then
    zenity --error --text="Chrome or Chromium was not found."
    exit 1
fi

RULES=()

# Collect hostname/IP mappings
while true; do
    FQDN=$(zenity --entry \
	--title="ChromeHostOverride" \
	--text="Enter the FQDN to map (leave empty to finish):")

    [[ $? -ne 0 ]] && exit 0
    [[ -z "${FQDN//[[:space:]]/}" ]] && break

    IP=$(zenity --entry \
	--title="ChromeHostOverride" \
	--text="Enter the IP address for $FQDN:")

    [[ $? -ne 0 ]] && exit 0

    # Validate FQDN and IP address
    if ! python3 - "$FQDN" "$IP" <<'PY'
import sys
import re
import ipaddress

fqdn, address = sys.argv[1:3]

valid = (
    len(fqdn.rstrip('.')) <= 253
    and all(
	re.fullmatch(
	    r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?',
	    label
	)
	for label in fqdn.rstrip('.').split('.')
    )
)

try:
    ipaddress.ip_address(address)
except ValueError:
    valid = False

sys.exit(0 if valid else 1)
PY
    then
	zenity --error \
	    --title="Invalid input" \
	    --text="Invalid FQDN or IP address.\nPlease try again."
	continue
    fi

    RULES+=("MAP $FQDN $IP")

    zenity --info \
	--timeout=2 \
	--title="Mapping added" \
	--text="$FQDN → $IP"
done

# Ensure at least one mapping exists
if [[ ${#RULES[@]} -eq 0 ]]; then
    exit 0
fi

# Build comma-separated resolver rules
HOST_RULES=$(IFS=', '; echo "${RULES[*]}")

# Confirm configuration
if ! zenity --question \
    --title="Confirm configuration" \
    --width=450 \
    --text="Chrome will launch with these mappings:\n\n$(printf '%s\n' "${RULES[@]}")\n\nProceed?"
then
    exit 0
fi

# Cache directory
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_DIR" || exit 1

# Find previous isolated Chrome profiles
shopt -s nullglob
OLD_PROFILES=("$CACHE_DIR"/IsolatedChrome_*)
shopt -u nullglob

# Keep only actual directories, excluding symbolic links
PREVIOUS_PROFILES=()

for PROFILE in "${OLD_PROFILES[@]}"; do
    if [[ -d "$PROFILE" && ! -L "$PROFILE" ]]; then
	PREVIOUS_PROFILES+=("$PROFILE")
    fi
done

# Ask whether to remove previous profiles
if [[ ${#PREVIOUS_PROFILES[@]} -gt 0 ]]; then

    if zenity --question \
	--title="Previous Chrome profiles found" \
	--width=450 \
	--text="Found ${#PREVIOUS_PROFILES[@]} previous isolated Chrome profile(s).\n\nWould you like to delete them before proceeding?"
    then
	for PROFILE in "${PREVIOUS_PROFILES[@]}"; do
	    rm -rf -- "$PROFILE" || {
		zenity --error \
		    --title="Cleanup error" \
		    --text="Could not remove:\n$PROFILE"
		exit 1
	    }
	done

	zenity --info \
	    --title="Cleanup complete" \
	    --text="Previous Chrome profiles have been removed."
    fi
fi

# Generate a unique timestamped profile directory
TIMESTAMP=$(date '+%Y%m%d_%H%M%S_%N')
USER_DATA_DIR="$CACHE_DIR/IsolatedChrome_${TIMESTAMP}"

# Launch Chrome
"$CHROME" \
    --incognito \
    --test-type \
    --user-data-dir="$USER_DATA_DIR" \
    --host-resolver-rules="$HOST_RULES" &
