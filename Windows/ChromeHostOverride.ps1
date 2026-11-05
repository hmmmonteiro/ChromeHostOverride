
# ChromeHostOverride - Windows
# Persistent hostname mappings and isolated Chrome sessions.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName = "ChromeHostOverride"

# ------------------------------------------------------------
# Paths and browser detection
# ------------------------------------------------------------

$ConfigDir = Join-Path $env:APPDATA "ChromeHostOverride"
$ConfigFile = Join-Path $ConfigDir "mappings.json"
$CacheDir = Join-Path $env:LOCALAPPDATA "ChromeHostOverride"

$ChromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)

$Chrome = $ChromePaths |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if (-not $Chrome) {
    [System.Windows.Forms.MessageBox]::Show(
	"Google Chrome was not found.",
	$AppName,
	"OK",
	"Error"
    )
    exit 1
}

New-Item -ItemType Directory -Path $ConfigDir, $CacheDir -Force |
    Out-Null

# ------------------------------------------------------------
# Load and save mappings
# ------------------------------------------------------------

function Load-Mappings {
    if (-not (Test-Path $ConfigFile)) {
	return
    }

    try {
	$data = Get-Content -LiteralPath $ConfigFile -Raw |
	    ConvertFrom-Json

	foreach ($mapping in $data.mappings) {
	    [void]$grid.Rows.Add(
		$false,
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
    $mappings = @()

    foreach ($row in $grid.Rows) {
	if ($row.IsNewRow) { continue }

	$fqdn = ([string]$row.Cells["FQDN"].Value).Trim()
	$ip = ([string]$row.Cells["IP"].Value).Trim()

	if (-not $fqdn -and -not $ip) { continue }

	$mappings += [PSCustomObject]@{
	    fqdn = $fqdn
	    ip	 = $ip
	}
    }

    $data = [PSCustomObject]@{
	mappings = @($mappings)
    }

    $tempFile = "$ConfigFile.tmp"

    try {
	$data | ConvertTo-Json -Depth 5 |
	    Set-Content -LiteralPath $tempFile -Encoding UTF8

	Move-Item -LiteralPath $tempFile `
	    -Destination $ConfigFile -Force

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
# Mapping validation
# ------------------------------------------------------------

function Test-Mapping {
    param($FQDN, $IP)

    $FQDN = $FQDN.Trim().TrimEnd('.')

    $pattern = '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'

    if ($FQDN -notmatch $pattern) {
	return $false
    }

    $parsedIP = $null

    return [System.Net.IPAddress]::TryParse(
	$IP.Trim(),
	[ref]$parsedIP
    )
}

function Get-ValidatedMappings {
    $result = @()
    $seen = @{}

    foreach ($row in $grid.Rows) {

	if ($row.IsNewRow) { continue }

	$fqdn = ([string]$row.Cells["FQDN"].Value).Trim()
	$ip = ([string]$row.Cells["IP"].Value).Trim()

	if (-not $fqdn -and -not $ip) { continue }

	if (-not (Test-Mapping $fqdn $ip)) {
	    [System.Windows.Forms.MessageBox]::Show(
		"Invalid FQDN or IP address:`r`n$fqdn → $ip",
		$AppName,
		"OK",
		"Error"
	    )
	    return $null
	}

	$key = $fqdn.TrimEnd('.').ToLowerInvariant()

	if ($seen.ContainsKey($key)) {
	    [System.Windows.Forms.MessageBox]::Show(
		"Duplicate hostname: $fqdn",
		$AppName,
		"OK",
		"Error"
	    )
	    return $null
	}

	$seen[$key] = $true

	$result += [PSCustomObject]@{
	    fqdn = $fqdn
	    ip	 = $ip
	    use	 = [bool]$row.Cells["Use"].Value
	}
    }

    return ,$result
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
    $selected = @($grid.SelectedRows |
	Where-Object { -not $_.IsNewRow })

    if ($selected.Count -eq 0) { return }

    $answer = [System.Windows.Forms.MessageBox]::Show(
	"Delete $($selected.Count) selected mapping(s)?",
	$AppName,
	"YesNo",
	"Question"
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
	foreach ($row in $selected) {
	    $grid.Rows.Remove($row)
	}
	[void](Save-Mappings)
    }
}.GetNewClosure())

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
}.GetNewClosure())

$form.Controls.Add($saveButton)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "Launch Chrome"
$launchButton.Location = New-Object System.Drawing.Point(590, 410)
$launchButton.Size = New-Object System.Drawing.Size(140, 32)
$launchButton.Anchor = "Bottom, Right"

$form.Controls.Add($launchButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Close"
$cancelButton.Location = New-Object System.Drawing.Point(480, 410)
$cancelButton.Size = New-Object System.Drawing.Size(100, 32)
$cancelButton.Anchor = "Bottom, Right"

$cancelButton.Add_Click({
    $form.Close()
}.GetNewClosure())

$form.Controls.Add($cancelButton)

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

    $rules = @()

    foreach ($mapping in $selected) {

	$parsedIP = [System.Net.IPAddress]::Parse($mapping.ip)

	$ipValue = $parsedIP.ToString()

	if ($parsedIP.AddressFamily -eq
	    [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
	    $ipValue = "[$ipValue]"
	}

	$rules += "MAP $($mapping.fqdn) $ipValue"
    }

    $hostRules = $rules -join ", "

    $summary = $rules -join "`r`n"

    $answer = [System.Windows.Forms.MessageBox]::Show(
	"Chrome will launch with these mappings:`r`n`r`n$summary`r`n`r`nProceed?",
	"Confirm configuration",
	"YesNo",
	"Question"
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
	return
    }

    # Save all mappings, not just the selected ones
    if (-not (Save-Mappings)) { return }

    # Find previous profiles
    $oldProfiles = @(
	Get-ChildItem -LiteralPath $CacheDir -Directory |
	Where-Object {
	    $_.Name -like "IsolatedChrome_*" -and
	    -not ($_.Attributes -band
		[System.IO.FileAttributes]::ReparsePoint)
	}
    )

    if ($oldProfiles.Count -gt 0) {

	$cleanup = [System.Windows.Forms.MessageBox]::Show(
	    "Found $($oldProfiles.Count) previous isolated Chrome profile(s).`r`n`r`nWould you like to delete them before proceeding?`r`n`r`nMake sure their Chrome sessions are closed.",
	    "Previous profiles found",
	    "YesNo",
	    "Question"
	)

	if ($cleanup -eq [System.Windows.Forms.DialogResult]::Yes) {
	    try {
		foreach ($profile in $oldProfiles) {
		    Remove-Item -LiteralPath $profile.FullName `
			-Recurse -Force -ErrorAction Stop
		}
	    }
	    catch {
		[System.Windows.Forms.MessageBox]::Show(
		    "Could not remove a previous profile:`r`n$($_.Exception.Message)",
		    $AppName,
		    "OK",
		    "Error"
		)
		return
	    }
	}
    }

    # Create a unique timestamped profile
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"

    $userDataDir = Join-Path $CacheDir "IsolatedChrome_$timestamp"

    if (Test-Path $userDataDir) {
	$userDataDir += "_" + [guid]::NewGuid().ToString("N").Substring(0,8)
    }

    # Launch Chrome
    $arguments = @(
	"--incognito"
	"--test-type"
	"--user-data-dir=`"$userDataDir`""
	"--host-resolver-rules=`"$hostRules`""
    ) -join " "

    try {
	Start-Process -FilePath $Chrome -ArgumentList $arguments `
	    -ErrorAction Stop

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

}.GetNewClosure())

# ------------------------------------------------------------
# Load database and display
# ------------------------------------------------------------

Load-Mappings

[void]$form.ShowDialog()
