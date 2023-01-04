$destination = 'C:\VeeamStaging\Confluence'

Get-ChildItem $destination -Include *.* -Recurse | ForEach  { $_.Delete()}