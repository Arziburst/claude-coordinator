#Requires -Version 7
# Parses only in PowerShell 7 (the ?? operator): check-scripts must hand it to pwsh, not to 5.1.
$x = $null ?? 1
$x
