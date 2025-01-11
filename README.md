Atlassian Cloud Backup with Veeam Backup & Replication
=========

Contains scripts to be used on Veeam Backup &amp; Replication in order to backup Atlassian Cloud applications.

# Working Procedure

1. Veeam Job starts and executes the Pre-Job script
2. The Pre-Job script Connects to Atlassian Cloud API and requests a backup.
3. The Pre-Job Downloads the backup file and stores it inside a user defined staging folder along with a PowerShell transcript log.
4. Veeam backups up the staging folder.
5. Veeam executes the Post-Job script which clears the staging folder.

# Usage

### ⚙ Step #1: Preparation

Create the backup staging folders, example:
- ```C:\VeeamStaging\Confluence```
- ```C:\VeeamStaging\Jira```

Get the PowerShell scripts from this repository and save them somewhere.

**Script Variables**

Configure the following variables on Pre-Job and Post-Job scripts:
- ```$destination``` Corresponds to a staging folder for each Atlassian App, if you are not using our default settings make sure to modify the values to point on your selected path.

Configure the following variables on Pre-Job scripts:
- ```$CMEntry``` It should correspond to the Credential Name inside the Windows Credential Manager see **Step #2**.
- ```$account``` The subdomain of your Atlassian cloud site company.atlassian.net
- ```$attachments``` Set true or false depending if you want to include attachments on your backup file.
- ```$cloud``` Set true if you want to export cloud backups, set to false to export server-compatible backups.

### ⚙ Step #2: API Credentials Store

In the scenario where you installed Veeam Backup & Replication with the default settings your job scripts will execute as ```NT AUTHORITY\SYSTEM```. In this case, if you open the Windows Credential Manager the script will fail because credentials are associated with the user they created. So, in order to run the script under Veeam’s default settings you have to store the API credentials under ```NT AUTHORITY\SYSTEM``` account.

How to store the Atlassian API credentials on ```NT AUTHORITY\SYSTEM``` account:

Requirements
- PsExec
- Administrative Privileges
- PowerShell

Navigate to the PsExec directory if it’s not an Environment Variable and execute the following command:

```
.\PsExec64 -i -s powershell.exe
```
- ```-i``` Starts the process in interactive mode.
- ```-s``` Runs the process as SYSTEM.

A new PowerShell window will appear on your screen, in order to verify you are under the SYSTEM account type the command ```whoami```.

To create a new credentials issue the following command:

```
New-StoredCredential -Target Atlassian -UserName <user@domain.tld> -Password <String> -Persist LOCALMACHINE
```
Verify the newly stored credential by issuing:

```
Get-StoredCredential -Target Atlassian
```

If you want to remove the credential issue the following command:

```
Remove-StoredCredential -Target Atlassian
```

### ⚙ Step #3: Job Configuration

Create a File share backup job for each staging folder.

While you configuring the jobs you need to specify pre and post job scripts:

**Confluence Backup Job**
- Storage → Advanced → Scripts
  - Run the following script before the job: ```/path/to/Confluence_Pre-Job.ps1```
  - Run the following script after the job: ```/path/to/Confluence_Post-Job.ps1```

**Jira Backup Job**
- Storage → Advanced → Scripts
  - Run the following script before the job: ```/path/to/Jira_Pre-Job.ps1```
  - Run the following script after the job: ```/path/to/Jira_Post-Job.ps1```

# Limitations

- You can run Jira backups every 48 Hours.
- You can run Confluence backups every 24 hours.

# Sources

- This repository contains scripts from: https://bitbucket.org/atlassianlabs/automatic-cloud-backup/src/master/
- Manage Atlassian API tokens: https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/

# License

This repository is licensed under the Apache License 2.0 license.

# Disclaimer

The contents in this repository provided AS IS with absolutely NO warranty. KASTERVO LTD is not responsible and without any limitation, for any errors, omissions, losses or damages arising from the use of this repository.