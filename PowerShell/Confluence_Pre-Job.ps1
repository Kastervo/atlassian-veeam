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
$CredentialName = 'Atlassian' # The name on Windows Credential Manager.
$destination = 'C:\VeeamStaging\Confluence' # Location on server where script is run to dump the backup zip file.
$attachments = 'true' # Tells the script whether or not to pull down the attachments as well.
$cloud     = 'true' # Tells the script whether to export the backup for Cloud or Server.
$today       = Get-Date -format yyyyMMdd-hhm
$BackupFilename = "confluence-backup-$today.zip" # The confluence backup file name.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

if ($PSVersionTable.PSVersion.Major -lt 4) {
    Write-Error "Script requires at least PowerShell version 4. Get it here: https://www.microsoft.com/en-us/download/details.aspx?id=40855"
}

Start-Transcript -Append $destination\ConfluenceBU.log

if(!(Test-Path -path $destination)){
    Write-Host "Folder is not present, creating folder"
    mkdir $destination
}
else{
    Write-Host "Path is already present"
}

# Get the credentials from Windows Credential Manager
$Cred = Get-StoredCredential -Target $CredentialName
$ATLUser = $Cred.UserName.ToString()
$auth = [System.Text.Encoding]::UTF8.GetBytes(("{0}:{1}" -f $ATLUser,([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Cred.Password)))))
$auth = [System.Convert]::ToBase64String($auth)

# Set authentication headers
$header = @{
    "Authorization" = "Basic "+$auth
    "Content-Type"="application/json"
    "Accept" = "application/json"
    }

# Set body
$body = @{
          cbAttachments=$attachments
          exportToCloud=$cloud
         }
$bodyjson = $body | ConvertTo-Json

# Set backup success message
$BackupSuccessMessage = @"
Confluence backup for $account has been completed.
Backup location: $destination
Backup File: $BackupFilename
"@

# Set Atlassian URLs
$BackupEndpointURL = "https://$account.atlassian.net/wiki/rest/obm/1.0/runbackup"
$BackupsStatusURL = "https://$account.atlassian.net/wiki/rest/obm/1.0/getprogress"

# Create a Confluence Cloud backup
try {
    $BackupResponse = Invoke-RestMethod -Method POST -Uri $BackupEndpointURL -Headers $header -Body $bodyjson
} catch {
    $BackupResponse = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($BackupResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $ResponseBody = $reader.ReadToEnd();
}

if ($BackupResponse.StatusCode -eq 200) {
    Write-Host $ResponseBody
} else {
    Write-Warning $ResponseBody
}

# Get Backup information
$GetBackupID = Invoke-WebRequest -Method Get -Headers $header -UseBasicParsing $BackupsStatusURL
$BackupStatus = convertfrom-json $GetBackupID.content

# Wait for backup to finish
do {
    $status = Invoke-RestMethod -Method Get -Headers $header -Uri $BackupsStatusURL
    $BackupStatus = convertfrom-json $GetBackupID.content
    $StatusOutput = $BackupStatus.alternativePercentage

    if ($StatusOutput -eq "100%") {
        Write-Host "Creating backup, please wait..."
    }

    Start-Sleep -Seconds 5
} while($StatusOutput -ne '100%')

# Download Backup
if ([bool]($status.PSObject.Properties.Name -match "failedMessage")) {
    Write-Error $status.failedMessage
} else {
    $BackupLocation = $BackupStatus.filename
    $DownloadURI = "https://$account.atlassian.net/wiki/download/$BackupLocation"

    Write-Host "Writing Backup contents..."
    Invoke-WebRequest -Method Get -Headers $header -UseBasicParsing -Uri $DownloadURI -OutFile (Join-Path -Path $destination -ChildPath $BackupFilename)
    Write-Host $BackupSuccessMessage
}