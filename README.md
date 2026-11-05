# ChromeHostOverride

A simple wrapper for sandboxed Chrome sessions with custom host overrides.

## Features

- Launches Google Chrome or Chromium with custom hostname-to-IP mappings.
- Supports multiple FQDN/IP pairs, including IPv4 and IPv6.
- Uses Chrome's `--host-resolver-rules` command-line option to override hostname resolution.
- Creates a separate, timestamped browser profile for every session.
- Optionally detects and removes previous isolated profiles.
- Provides a simple graphical interface through Zenity.

## Requirements

** For Linux **
- Bash
- Google Chrome or Chromium (supporting `--host-resolver-rules`)
- Python 3
- [Zenity](https://help.gnome.org/users/zenity/stable/) (graphical dialogs)

On Debian/Ubuntu:

```bash
sudo apt install zenity python3
```

## Installation

Clone the repository:

```bash
git clone https://github.com/hmmmonteiro/ChromeHostOverride.git
cd ChromeHostOverride/Linux
```

Make the script executable:

```bash
chmod +x ChromeHostOverride.sh
```

## Usage

Run:

```bash
./ChromeHostOverride.sh
```

The graphical prompts will guide you through:

1. Entering an FQDN and its corresponding IP address.
2. Adding additional hostname mappings, if needed.
3. Reviewing and confirming the configuration.
4. Optionally clearing previous isolated Chrome profiles.
5. Launching a new Chrome or Chromium session.

## How it works

ChromeHostOverride uses Chrome's built-in `--host-resolver-rules` command-line option to redirect specified hostnames to supplied IP addresses, without modifying the system's DNS configuration or hosts file.

Each launch receives its own timestamped user-data directory under:

```text
~/.cache/IsolatedChrome_YYYYMMDD_HHMMSS_NNNNNNNNN/
```

This provides separation of browser data, cookies and session state from your regular Chrome profile and other isolated sessions.

Previous profiles can optionally be removed when launching a new session.

### Security note

ChromeHostOverride provides browser-profile isolation, not an additional security sandbox.

It does not provide operating-system-level isolation of processes, filesystem access or network access. Chrome's own built-in security sandbox remains responsible for browser process isolation.

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See [LICENSE](LICENSE) for details.
