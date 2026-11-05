
# ChromeHostOverride
# Launch Chrome/Chromium with custom hostname-to-IP mappings
# and a fresh, isolated browser profile.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$CacheDir = Join-Path $env:LOCALAPPDATA "ChromeHostOverride"

# Locate Chrome
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
	"ChromeHostOverride",
	"OK",
	"Error"
    )
    exit 1
}

# ------------------------------------------------------------
# Main window
# ------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "ChromeHostOverride"
$form.Size = New-Object System.Drawing.Size(620, 390)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter the hostname and corresponding IP address:"
$label.Location = New-Object System.Drawing.Point(15, 15)
$label.Size = New-Object System.Drawing.Size(570, 25)
$form.Controls.Add($label)

# Mapping grid
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(15, 45)
$grid.Size = New-Object System.Drawing.Size(575, 220)
$grid.AllowUserToAddRows = $true
$grid.AllowUserToDeleteRows = $true
$grid.AutoSizeColumnsMode = "Fill"
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $false

[void]$grid.Columns.Add("FQDN", "FQDN / Hostname")
[void]$grid.Columns.Add("IP", "IP Address")

$form.Controls.Add($grid)

# ------------------------------------------------------------
# Buttons
# ------------------------------------------------------------

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = "Remove selected"
$removeButton.Location = New-Object System.Drawing.Point(15, 280)
$removeButton.Size = New-Object System.Drawing.Size(130, 30)

$removeButton.Add_Click({
    foreach ($row in @($grid.SelectedRows)) {
	if (-not $row.IsNewRow) {
	    $grid.Rows.Remove($row)
	}
    }
}.GetNewClosure())

$form.Controls.Add($removeButton)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "Launch Chrome"
$launchButton.Location = New-Object System.Drawing.Point(365, 320)
$launchButton.Size = New-Object System.Drawing.Size(110, 30)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object System.Drawing.Point(480, 320)
$cancelButton.Size = New-Object System.Drawing.Size(110, 30)
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

$form.Controls.Add($launchButton)
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton

# ------------------------------------------------------------
# Validate mappings and launch
# ------------------------------------------------------------

$launchButton.Add_Click({

    $grid.EndEdit()

    $Rules = @()

    foreach ($row in $grid.Rows) {

	if ($row.IsNewRow) { continue }

	$FQDN = ([string]$row.Cells[0].Value).Trim()
	$IP = ([string]$row.Cells[1].Value).Trim()

	if (-not $FQDN -and -not $IP) { continue }

	# Validate FQDN
	$FQDNPattern = '^(?=.{1,253}\.?$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.?$'

	if ($FQDN -notmatch $FQDNPattern) {
	    [System.Windows.Forms.MessageBox]::Show(
		"Invalid FQDN: $FQDN",
		"Validation error",
		"OK",
		"Error"
	    )
	    return
	}

	# Validate IP address
	$ParsedIP = $null

	if (-not [System.Net.IPAddress]::TryParse($IP, [ref]$ParsedIP)) {
	    [System.Windows.Forms.MessageBox]::Show(
		"Invalid IP address: $IP",
		"Validation error",
		"OK",
		"Error"
	    )
	    return
	}

	$IPValue = $ParsedIP.ToString()

	# Chrome requires brackets around IPv6 literals
	if ($ParsedIP.AddressFamily -eq
	    [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
	    $IPValue = "[$IPValue]"
	}

	$Rules += "MAP $FQDN $IPValue"
    }

    if ($Rules.Count -eq 0) {
	[System.Windows.Forms.MessageBox]::Show(
	    "Please enter at least one valid mapping.",
	    "ChromeHostOverride",
	    "OK",
	    "Warning"
	)
	return
    }

    $HostRules = $Rules -join ", "

    $Summary = $Rules -join "`r`n"

    $Confirmation = [System.Windows.Forms.MessageBox]::Show(
	"Chrome will launch with the following mappings:`r`n`r`n$Summary`r`n`r`nProceed?",
	"Confirm configuration",
	"YesNo",
	"Question"
    )

    if ($Confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
	return
    }

    # --------------------------------------------------------
    # Previous profile cleanup
    # --------------------------------------------------------

    New-Item -ItemType Directory -Path $CacheDir -Force |
	Out-Null

    $OldProfiles = @(
	Get-ChildItem -LiteralPath $CacheDir -Directory |
	Where-Object {
	    $_.Name -like "IsolatedChrome_*" -and
	    -not ($_.Attributes -band
		[System.IO.FileAttributes]::ReparsePoint)
	}
    )

    if ($OldProfiles.Count -gt 0) {

	$Cleanup = [System.Windows.Forms.MessageBox]::Show(
	    "Found $($OldProfiles.Count) previous isolated Chrome profile(s).`r`n`r`nWould you like to delete them before proceeding?`r`n`r`nMake sure no corresponding Chrome sessions are running.",
	    "Previous profiles found",
	    "YesNo",
	    "Question"
	)

	if ($Cleanup -eq [System.Windows.Forms.DialogResult]::Yes) {

	    try {
		foreach ($Profile in $OldProfiles) {
		    Remove-Item -LiteralPath $Profile.FullName `
			-Recurse -Force -ErrorAction Stop
		}
	    }
	    catch {
		[System.Windows.Forms.MessageBox]::Show(
		    "Could not remove a previous profile:`r`n$($_.Exception.Message)",
		    "Cleanup error",
		    "OK",
		    "Error"
		)
		return
	    }
	}
    }

    # --------------------------------------------------------
    # Create fresh timestamped profile
    # --------------------------------------------------------

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"

    $UserDataDir = Join-Path $CacheDir "IsolatedChrome_$Timestamp"

    # Start Chrome
    $Arguments = @(
	"--incognito"
	"--test-type"
	"--user-data-dir=`"$UserDataDir`""
	"--host-resolver-rules=`"$HostRules`""
    ) -join " "

    try {
	Start-Process -FilePath $Chrome -ArgumentList $Arguments `
	    -ErrorAction Stop

	$form.DialogResult = [System.Windows.Forms.DialogResult]::OK
	$form.Close()
    }
    catch {
	[System.Windows.Forms.MessageBox]::Show(
	    "Could not launch Chrome:`r`n$($_.Exception.Message)",
	    "Launch error",
	    "OK",
	    "Error"
	)
    }

}.GetNewClosure())

# Display GUI
[void]$form.ShowDialog()
