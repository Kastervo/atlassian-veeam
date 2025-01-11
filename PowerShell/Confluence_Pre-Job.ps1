<#
.SYNOPSIS

Connects to Confluence Cloud via API, creates a backup and downloads it.
---------------------------------------------------------------------------------------------
.NOTES

The Credential Manager PowerShell Module is required to run excecute this script.
Install it by running the command below on an elevated PowerShell Window:

Install-Module -Name CredentialManager
---------------------------------------------------------------------------------------------
.LINK

PSGallery: https://www.powershellgallery.com/packages/CredentialManager/2.0
Generate an API token: https://confluence.atlassian.com/cloud/api-tokens-938839638.html
---------------------------------------------------------------------------------------------
#>

# Edit the following variables to access your cloud site.
$account     = 'youratlassianconfluence' # Atlassian subdomain i.e. whateverproceeds.atlassian.net.
$CMEntry = 'Atlassian' # The credential entry name on Windows Credential Manager.
$destination = 'C:\VeeamStaging\Confluence' # Location on server where script is run to dump the backup zip file.
$attachments = 'true' # Tells the script whether or not to pull down the attachments as well.
$cloud     = 'true' # Tells the script whether to export the backup for Cloud or Server.
$today       = Get-Date -format yyyyMMdd-hhm
$BackupFilename = "confluence-backup-$today.zip" # The confluence backup file name.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

# Check the PowerShell version.
if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Error "Script requires at least PowerShell version 4. Get it here: https://www.microsoft.com/en-us/download/details.aspx?id=40855"
}

# Set Atlassian URLs
$BackupEndpointURL = "https://$account.atlassian.net/wiki/rest/obm/1.0/runbackup"
$BackupsStatusURL = "https://$account.atlassian.net/wiki/rest/obm/1.0/getprogress"

# Set the working directory.
function Set-Path {
	param (
		[Parameter(Mandatory = $true)]
		[string]$WorkDir
	)

	if(!(Test-Path -path $WorkDir)){
		Write-Host "Folder is not present, creating folder"
		mkdir $WorkDir
	}
	else{
		Write-Host "Path is already present"
	}
}

# Load credentials and generate authentication headers
function Get-AuthHeaders {
	param (
		[Parameter(Mandatory = $true)]
		[string]$CMEntry
	)

	# Get the credentials from Windows Credential Manager
	$Cred = Get-StoredCredential -Target $CMEntry
	if (-not $Cred) {
		throw "Credential $CMEntry not found in Windows Credential Manager."
	}
	$ATLUser = $Cred.UserName.ToString()
	$auth = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $ATLUser,([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Cred.Password)))))
	$authBase64 = [System.Convert]::ToBase64String($auth)
	return @{
		"Authorization" = "Basic $authBase64"
		"Content-Type"="application/json"
		"Accept" = "application/json"
		}
}

# Create a Confluence Cloud backup
function Request-Backup {
	param (
		[Parameter(Mandatory = $true)]
		[string]$BackupEndpoint,

		[Parameter(Mandatory = $true)]
		[hashtable]$Headers
	)

	# Set body
	$body = @{
		cbAttachments=$attachments
		exportToCloud=$cloud
	}
	$bodyjson = $body | ConvertTo-Json -Depth 2

	try {
		$BackupResponse = Invoke-RestMethod -Method POST -Uri $BackupEndpoint -Headers $Headers -Body $bodyjson
		Write-Host "Backup request succeeded."
		Write-Host $BackupResponse
		return $BackupResponse
 	} catch {
		Write-Warning "Error initiating backup: $($_.Exception.Message)"

		if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
			$BackupResponseStream = $_.Exception.Response.GetResponseStream()
			$reader = New-Object System.IO.StreamReader($BackupResponseStream)
			$reader.BaseStream.Position = 0
			$reader.DiscardBufferedData()
			$ResponseBody = $reader.ReadToEnd()
			Write-Warning "Response body: $ResponseBody"
		} else {
			Write-Warning "No response details available."
		}

		return $null
	}
}

# Monitor backup status
function Wait-ForBackup {
	param (
		[Parameter(Mandatory = $true)]
		[string]$StatusUrl,

		[Parameter(Mandatory = $true)]
		[hashtable]$Headers,

		[int]$TimeoutSeconds = 600
	)

	$Start = Get-Date
	while ((Get-Date) - $Start -lt (New-TimeSpan -Seconds $TimeoutSeconds)) {
		try {
			$Status = Invoke-RestMethod -Method Get -Headers $Headers -Uri $StatusUrl
			if ($Status.alternativePercentage -eq 100 -and $Status.fileName) {
				return $Status
			} elseif ($Status.failedMessage) {
				throw "Backup failed: $($Status.failedMessage)"
			} else {
				Write-Host "Progress: $($Status.alternativePercentage)"
			}
		} catch {
			Write-Warning "Error retrieving backup status: $($_.Exception.Message)"
			break
		}
		Start-Sleep -Seconds 5
	}
	throw "Backup did not complete."
}

function Get-Backup {
	param (
		[Parameter(Mandatory = $true)]
		[array]$BackupStatus,

		[Parameter(Mandatory = $true)]
		[string]$Account,

		[Parameter(Mandatory = $true)]
		[string]$Destination,

		[Parameter(Mandatory = $true)]
		[string]$BackupFilename,

		[Parameter(Mandatory = $true)]
		[hashtable]$Headers
	)

	if ([bool]($BackupStatus.PSObject.Properties.Name -match "failedMessage")) {
		throw "Backup failed: $($BackupStatus.failedMessage)"
	}

	$BackupLocation = $BackupStatus.fileName
	$DownloadURI = "https://$account.atlassian.net/wiki/download/$BackupLocation"
	Write-Host "Download URI:" $DownloadURI
	$BackupPath = Join-Path -Path $destination -ChildPath $BackupFilename
	
	Write-Host "Downloading backup file to: $BackupPath"
	try {
		Invoke-WebRequest -Method Get -Headers $Headers -Uri $DownloadURI -OutFile $BackupPath
		Write-Host "Backup completed successfully. File saved at: $BackupPath"
	} catch {
		throw "Error downloading backup: $($_.Exception.Message)"
	}
}

# 0. Enable logging:
Start-Transcript -Append $destination\ConfluenceBU.log

# 1. Working directory configuration:
Set-Path -WorkDir $destination

# 2. Set authentication headers:
$headers = Get-AuthHeaders -CMEntry $CMEntry

# 3. Request a backup to be created:
Request-Backup -BackupEndpoint $BackupEndpointURL -Headers $headers

# 4. Register the backup status:
$BackupState = Wait-ForBackup -StatusUrl $BackupsStatusURL -Headers $headers

# 5. Download the backup:
Get-Backup -BackupStatus $BackupState -Account $Account -Destination $destination -BackupFilename $BackupFilename -Headers $headers

# 6. Stop logging:
Stop-Transcript