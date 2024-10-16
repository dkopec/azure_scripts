<#
.SYNOPSIS
This script forces a password change for specified Microsoft 365 users or all users if none are specified, except those in the exclusion list.

.DESCRIPTION
The script connects to Microsoft 365 using the MSOnline module, retrieves specified user accounts or all user accounts, and forces a password change for each user except those specified in the exclusion list. The exclusion list and target user list can be provided as parameters or read from files.

.PARAMETER ExcludedAccounts
An array of user principal names (UPNs) to be excluded from the password reset.

.PARAMETER ExcludedAccountsFile
A file path containing a list of user principal names (UPNs) to be excluded from the password reset.

.PARAMETER TargetAccounts
An array of user principal names (UPNs) to be targeted for the password reset.

.PARAMETER TargetAccountsFile
A file path containing a list of user principal names (UPNs) to be targeted for the password reset.

.EXAMPLE
.\Set-M365UserForceChangePassswordOnly.ps1 -ExcludedAccounts @("user1@domain.com", "user2@domain.com")

.EXAMPLE
.\Set-M365UserForceChangePassswordOnly.ps1 -ExcludedAccountsFile "C:\path\to\excluded_accounts.txt"

.EXAMPLE
.\Set-M365UserForceChangePassswordOnly.ps1 -TargetAccounts @("user3@domain.com", "user4@domain.com")

.EXAMPLE
.\Set-M365UserForceChangePassswordOnly.ps1 -TargetAccountsFile "C:\path\to\target_accounts.txt"

.NOTES
- Requires the MSOnline module.
- The script logs its actions to a file named log-<timestamp>.txt.
- The script will exit if the specified exclusion or target file does not exist.

#>
param (
  [string[]]$ExcludedAccounts,
  [string]$ExcludedAccountsFile,
  [string[]]$TargetAccounts,
  [string]$TargetAccountsFile
)
start-transcript -Path log-$(get-date -format o).txt -NoClobber -Force
Write-Host "Install MSOnline Module"
Install-Module MSOnline
Write-Host "Import Module"
Import-Module MSOnline
Write-Host "Connect to MS Online"
Connect-MSOLService

# Read excluded accounts from file if provided
Write-Host "Import Excluded users"
if ($ExcludedAccountsFile) {
  if (Test-Path $ExcludedAccountsFile) {
    $fileExcludedAccounts = Get-Content -Path $ExcludedAccountsFile
    Write-Host $fileExcludedAccounts
    $ExcludedAccounts += $fileExcludedAccounts
  }
  else {
    Write-Error "The file $ExcludedAccountsFile does not exist."
    exit
  }
}

# Read target accounts from file if provided
Write-Host "Import Target users"
if ($TargetAccountsFile) {
  if (Test-Path $TargetAccountsFile) {
    $fileTargetAccounts = Get-Content -Path $TargetAccountsFile
    Write-Host $fileTargetAccounts
    $TargetAccounts += $fileTargetAccounts
  }
  else {
    Write-Error "The file $TargetAccountsFile does not exist."
    exit
  }
}

# Get target users or all users if no target specified
Write-Host "Get target users or all users"
if ($TargetAccounts) {
  $users = @()
  foreach ($target in $TargetAccounts) {
    $user = Get-MsolUser -UserPrincipalName $target
    if ($user) {
      $users += $user
    }
  }
} else {
  $users = Get-MsolUser -All
}

# Loop through each user and reset their password if they are not in the excluded list
Write-Host "Loop through users"
foreach ($user in $users) {
  if ($ExcludedAccounts -notcontains $user.UserPrincipalName) {
    Set-MsolUserPassword -UserPrincipalName $user.UserPrincipalName -ForceChangePassword $true -ForceChangePasswordOnly $true
    Write-Output "Force Change password for $($user.UserPrincipalName)"
  }
  else {
    Write-Output "Skipping $($user.UserPrincipalName)"
  }
}
Stop-Transcript