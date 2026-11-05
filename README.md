# ChromeHostOverride

A simple wrapper for sandboxed Chrome sessions with custom host overrides.

## Features

- Launches Google Chrome or Chromium with custom hostname-to-IP mappings.
- Supports multiple FQDN/IP pairs, including IPv4 and IPv6.
- Uses Chrome's `--host-resolver-rules` command-line option to override hostname resolution.
- Creates a separate, timestamped browser profile for every session.
- Optionally detects and removes previous isolated profiles.
- Provides a graphical interface on both Linux and Windows.

## Requirements

### Linux

- Bash
- Google Chrome or Chromium (supporting `--host-resolver-rules`)
- Python 3
- [Zenity](https://help.gnome.org/users/zenity/stable/) (graphical dialogs)

On Debian/Ubuntu:

```bash
sudo apt install zenity python3
```

### Windows

- Windows 10 or later
- Windows PowerShell 5.1 or PowerShell 7
- Google Chrome or Chromium (supporting `--host-resolver-rules`)

The Windows implementation uses Windows Forms for its graphical interface. No additional GUI dependencies are required.

## Installation

Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/ChromeHostOverride.git
cd ChromeHostOverride
```

### Linux

Make the script executable:

```bash
chmod +x Linux/ChromeHostOverride.sh
```

### Windows

No installation is required. The PowerShell script can be executed directly.

## Usage

### Linux

Run:

```bash
./Linux/ChromeHostOverride.sh
```

### Windows

Run from PowerShell:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\Windows\ChromeHostOverride.ps1"
```

Or

Double-click:

`Windows/ChromeHostOverride.bat`

Alternatively, run it from Command Prompt:

```batch
ChromeHostOverride.bat
```

The graphical interface will guide you through:

1. Entering an FQDN and its corresponding IP address.
2. Adding additional hostname mappings, if needed.
3. Reviewing and confirming the configuration.
4. Optionally clearing previous isolated Chrome profiles.
5. Launching a new Chrome or Chromium session.

The Windows implementation provides an editable table for managing multiple mappings, while the Linux implementation uses individual graphical prompts.

## How it works

ChromeHostOverride uses Chrome's built-in `--host-resolver-rules` command-line option to redirect specified hostnames to supplied IP addresses, without modifying the system's DNS configuration or hosts file.

Each launch receives its own timestamped user-data directory.

**Linux:**

```text
~/.cache/IsolatedChrome_YYYYMMDD_HHMMSS_NNNNNNNNN/
```

**Windows:**

```text
%LOCALAPPDATA%\ChromeHostOverride\IsolatedChrome_YYYYMMDD_HHMMSS_NNN/
```

This provides separation of browser data, cookies and session state from your regular Chrome profile and other isolated sessions.

Previous profiles can optionally be removed when launching a new session.

## Security note

ChromeHostOverride provides browser-profile isolation, not an additional security sandbox.

It does not provide operating-system-level isolation of processes, filesystem access or network access. Chrome's own built-in security sandbox remains responsible for browser process isolation.

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See [LICENSE](LICENSE) for details.
