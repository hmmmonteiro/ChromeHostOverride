# ChromeHostOverride - Windows
# Persistent hostname mappings and isolated Chrome sessions.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName = "ChromeHostOverride"

# ------------------------------------------------------------
# Paths and browser detection
# ------------------------------------------------------------

$ConfigDir  = Join-Path $env:APPDATA      "ChromeHostOverride"
$ConfigFile = Join-Path $ConfigDir        "mappings.json"
$CacheDir   = Join-Path $env:LOCALAPPDATA "ChromeHostOverride"

function Find-Chrome {
    # Prefer the registered App Path (matches what the user actually launches),
    # then fall back to well-known install locations.
    $registryKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    )

    foreach ($key in $registryKeys) {
        try {
            $value = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
            if ($value -and (Test-Path -LiteralPath $value)) {
                return $value
            }
        }
        catch { }
    }

    $candidatePaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )

    foreach ($path in $candidatePaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

$Chrome = Find-Chrome

if (-not $Chrome) {
    [System.Windows.Forms.MessageBox]::Show(
        "Google Chrome was not found.",
        $AppName,
        "OK",
        "Error"
    )
    exit 1
}

New-Item -ItemType Directory -Path $ConfigDir, $CacheDir -Force | Out-Null

# ------------------------------------------------------------
# Grid row extraction (shared by save and validate)
# ------------------------------------------------------------

function Get-GridRows {
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }

        $fqdn = ([string]$row.Cells["FQDN"].Value).Trim()
        $ip   = ([string]$row.Cells["IP"].Value).Trim()

        if (-not $fqdn -and -not $ip) { continue }

        [PSCustomObject]@{
            Row  = $row
            FQDN = $fqdn
            IP   = $ip
            Use  = [bool]$row.Cells["Use"].Value
        }
    }
}

# ------------------------------------------------------------
# Load and save mappings
# ------------------------------------------------------------

function Load-Mappings {
    if (-not (Test-Path -LiteralPath $ConfigFile)) { return }

    try {
        $data = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json

        foreach ($mapping in $data.mappings) {
            [void]$grid.Rows.Add(
                [bool]$mapping.use,
                $mapping.fqdn,
                $mapping.ip
            )
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not read the mapping database:`r`n$($_.Exception.Message)",
            $AppName,
            "OK",
            "Error"
        )
    }
}

function Save-Mappings {
    $mappings = foreach ($entry in Get-GridRows) {
        [PSCustomObject]@{
            fqdn = $entry.FQDN
            ip   = $entry.IP
            use  = $entry.Use
        }
    }

    $data = [PSCustomObject]@{ mappings = @($mappings) }
    $tempFile = "$ConfigFile.tmp"

    try {
        $data | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $tempFile -Encoding UTF8

        # Atomic replace when possible; fall back to Move-Item on non-NTFS or network shares.
        try {
            if (Test-Path -LiteralPath $ConfigFile) {
                [System.IO.File]::Replace($tempFile, $ConfigFile, $null)
            }
            else {
                Move-Item -LiteralPath $tempFile -Destination $ConfigFile -Force
            }
        }
        catch {
            Move-Item -LiteralPath $tempFile -Destination $ConfigFile -Force
        }

        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not save mappings:`r`n$($_.Exception.Message)",
            $AppName,
            "OK",
            "Error"
        )
        return $false
    }
}

# ------------------------------------------------------------
# Mapping validation (DNS RFC 1035 / RFC 1123)
# ------------------------------------------------------------
#
# Hostname rules enforced here:
#   * Total length 1-253 characters.
#   * Labels 1-63 characters, separated by dots.
#   * Each label starts and ends with a letter or digit.
#   * Label characters: A-Z, a-z, 0-9, hyphen (-).  Underscores are
#     NOT valid in a hostname (they appear only in service records
#     like _http._tcp).  Underscores in Windows host files are a
#     compatibility hack, not RFC-compliant.
#   * No leading or trailing dot (a single trailing dot is stripped
#     before validation as it denotes an FQDN, which is equivalent).
#   * At least one label; single-label names (e.g. "localhost") are
#     allowed because they are valid hostnames under RFC 1035 and
#     are commonly used in local development.
#
function Test-Mapping {
    param([string]$FQDN, [string]$IP)

    $FQDN = $FQDN.Trim().TrimEnd('.')

    # 1-253 chars; one or more dot-separated labels, each 1-63 chars,
    # starting/ending with alphanumeric, hyphens allowed inside.
    $pattern = '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$'

    if ($FQDN -notmatch $pattern) { return $false }

    $parsedIP = $null
    return [System.Net.IPAddress]::TryParse($IP.Trim(), [ref]$parsedIP)
}

function Get-ValidatedMappings {
    $result = @()
    $seen   = @{}

    $entries = @(Get-GridRows)

    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]

        if (-not (Test-Mapping $entry.FQDN $entry.IP)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Invalid FQDN or IP address on row $($i + 1):`r`n$($entry.FQDN) → $($entry.IP)",
                $AppName,
                "OK",
                "Error"
            )
            return $null
        }

        $key = $entry.FQDN.TrimEnd('.').ToLowerInvariant()

        if ($seen.ContainsKey($key)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Duplicate hostname on row $($i + 1): $($entry.FQDN)",
                $AppName,
                "OK",
                "Error"
            )
            return $null
        }

        $seen[$key] = $true

        $result += [PSCustomObject]@{
            fqdn = $entry.FQDN
            ip   = $entry.IP
            use  = $entry.Use
        }
    }

    return ,$result
}

# ------------------------------------------------------------
# Chrome rule formatting
# ------------------------------------------------------------

function Format-HostResolverRule {
    param([string]$FQDN, [System.Net.IPAddress]$IP)

    $value = if ($IP.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        "[$($IP.ToString())]"
    }
    else {
        $IP.ToString()
    }

    "MAP $FQDN $value"
}

# ------------------------------------------------------------
# Main window
# ------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = $AppName
$form.Size = New-Object System.Drawing.Size(760, 490)
$form.MinimumSize = New-Object System.Drawing.Size(760, 490)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select mappings for this session. Edit, add or remove saved mappings below."
$label.Location = New-Object System.Drawing.Point(15, 15)
$label.Size = New-Object System.Drawing.Size(710, 25)
$form.Controls.Add($label)

# ------------------------------------------------------------
# Mapping grid
# ------------------------------------------------------------

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 45)
$grid.Size = New-Object System.Drawing.Size(715, 310)
$grid.Anchor = "Top, Bottom, Left, Right"
$grid.AllowUserToAddRows = $true
$grid.AllowUserToDeleteRows = $true
$grid.AutoSizeColumnsMode = "Fill"
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $true

$useColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$useColumn.Name = "Use"
$useColumn.HeaderText = "Use"
$useColumn.FillWeight = 12
[void]$grid.Columns.Add($useColumn)

$fqdnColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$fqdnColumn.Name = "FQDN"
$fqdnColumn.HeaderText = "FQDN / Hostname"
$fqdnColumn.FillWeight = 44
[void]$grid.Columns.Add($fqdnColumn)

$ipColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$ipColumn.Name = "IP"
$ipColumn.HeaderText = "IP Address"
$ipColumn.FillWeight = 44
[void]$grid.Columns.Add($ipColumn)

$form.Controls.Add($grid)

# ------------------------------------------------------------
# Buttons
# ------------------------------------------------------------

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = "Delete selected"
$deleteButton.Location = New-Object System.Drawing.Point(15, 370)
$deleteButton.Size = New-Object System.Drawing.Size(125, 32)
$deleteButton.Anchor = "Bottom, Left"

$deleteButton.Add_Click({
    $selected = @($grid.SelectedRows | Where-Object { -not $_.IsNewRow })
    if ($selected.Count -eq 0) { return }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Delete $($selected.Count) selected mapping(s)?",
        $AppName,
        "YesNo",
        "Question"
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        foreach ($row in $selected) { $grid.Rows.Remove($row) }
        [void](Save-Mappings)
    }
})

$form.Controls.Add($deleteButton)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "Save mappings"
$saveButton.Location = New-Object System.Drawing.Point(150, 370)
$saveButton.Size = New-Object System.Drawing.Size(125, 32)
$saveButton.Anchor = "Bottom, Left"

$saveButton.Add_Click({
    $grid.EndEdit()
    $mappings = Get-ValidatedMappings
    if ($null -eq $mappings) { return }
    [void](Save-Mappings)
})

$form.Controls.Add($saveButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Close"
$cancelButton.Location = New-Object System.Drawing.Point(480, 410)
$cancelButton.Size = New-Object System.Drawing.Size(100, 32)
$cancelButton.Anchor = "Bottom, Right"

$cancelButton.Add_Click({ $form.Close() })

$form.Controls.Add($cancelButton)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "Launch Chrome"
$launchButton.Location = New-Object System.Drawing.Point(590, 410)
$launchButton.Size = New-Object System.Drawing.Size(140, 32)
$launchButton.Anchor = "Bottom, Right"

$form.Controls.Add($launchButton)

# ------------------------------------------------------------
# Launch Chrome
# ------------------------------------------------------------

$launchButton.Add_Click({

    $grid.EndEdit()

    $mappings = Get-ValidatedMappings
    if ($null -eq $mappings) { return }

    $selected = @($mappings | Where-Object { $_.use })

    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select at least one mapping for this session.",
            $AppName,
            "OK",
            "Warning"
        )
        return
    }

    $rules = foreach ($mapping in $selected) {
        $parsedIP = [System.Net.IPAddress]::Parse($mapping.ip)
        Format-HostResolverRule -FQDN $mapping.fqdn -IP $parsedIP
    }

    $hostRules = $rules -join ", "
    $summary   = $rules -join "`r`n"

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Chrome will launch with these mappings:`r`n`r`n$summary`r`n`r`nProceed?",
        "Confirm configuration",
        "YesNo",
        "Question"
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    # Persist all mappings, not just the selected ones.
    if (-not (Save-Mappings)) { return }

    # ------------------------------------------------------------------
    # Clean up previous isolated profiles (non-fatal on failure)
    # ------------------------------------------------------------------
    $oldProfiles = @(
        Get-ChildItem -LiteralPath $CacheDir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "IsolatedChrome_*" -and
            -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
        }
    )

    if ($oldProfiles.Count -gt 0) {
        $cleanup = [System.Windows.Forms.MessageBox]::Show(
            "Found $($oldProfiles.Count) previous isolated Chrome profile(s).`r`n`r`nDelete them before proceeding?`r`n`r`n(Make sure their Chrome sessions are closed.)",
            "Previous profiles found",
            "YesNo",
            "Question"
        )

        if ($cleanup -eq [System.Windows.Forms.DialogResult]::Yes) {
            foreach ($profile in $oldProfiles) {
                try {
                    Remove-Item -LiteralPath $profile.FullName -Recurse -Force -ErrorAction Stop
                }
                catch {
                    # Skip locked profiles; do not block the launch.
                    Write-Warning "Could not remove '$($profile.Name)': $($_.Exception.Message)"
                }
            }
        }
    }

    # ------------------------------------------------------------------
    # Create a unique timestamped profile
    # ------------------------------------------------------------------
    $timestamp   = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $userDataDir = Join-Path $CacheDir "IsolatedChrome_$timestamp"

    if (Test-Path -LiteralPath $userDataDir) {
        $userDataDir += "_" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    }

    # ------------------------------------------------------------------
    # Launch Chrome. Pass args as an array; Start-Process will quote
    # elements containing spaces, so do NOT add your own quotes around
    # the --host-resolver-rules value.
    # ------------------------------------------------------------------
    $arguments = @(
        "--incognito"
        "--test-type"
        "--no-first-run"
        "--no-default-browser-check"
        "--user-data-dir=$userDataDir"
        "--host-resolver-rules=$hostRules"
    )

    try {
        Start-Process -FilePath $Chrome -ArgumentList $arguments -ErrorAction Stop
        $form.Close()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not launch Chrome:`r`n$($_.Exception.Message)",
            $AppName,
            "OK",
            "Error"
        )
    }
})

# ------------------------------------------------------------
# Load database and display
# ------------------------------------------------------------

Load-Mappings
[void]$form.ShowDialog()