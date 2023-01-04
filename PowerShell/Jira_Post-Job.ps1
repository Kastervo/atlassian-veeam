$destination = 'C:\VeeamStaging\Jira'

Get-ChildItem $destination -Include *.* -Recurse | ForEach  { $_.Delete()}