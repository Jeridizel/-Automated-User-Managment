$atlassian_id = ''
$atlassian_token = ''

$confluence_token = ''
$email = ''

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFileName = "confluence.log"
$LogFilePath = Join-Path -Path $ScriptDir -ChildPath $LogFileName

function Set-AuthorizeVariable {
    param (
        $username,
        $APIkey
    )
    $password = ConvertTo-SecureString $APIkey -AsPlainText
    return New-Object System.Management.Automation.PSCredential ($username, $password)
}
$Auth = Set-AuthorizeVariable -username $email -APIkey $confluence_token

function GetAtlassianOrgId {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer your_token_here")

    $response = Invoke-RestMethod 'https://api.atlassian.com/admin/v1/orgs' -Method 'GET' -Headers $headers
    return $response.data    
}
$OrgId = GetAtlassianOrgId | Select-Object -ExpandProperty id

function Log-Error {
    param(
        [string]$ScriptName,
        [int]$LineNumber,
        [string]$ErrorMessage,
        [string]$LogFilePath,

        [string]$User_Email = "",
        [string]$Group_Name = ""
    )
    $error_msg = "Script: $ScriptName`n"
    $error_msg += "Line: $LineNumber`n"

    if ($User_Email) { $error_msg += "Email_of_User: $User_Email`n" }
    if ($Group_Name) { $error_msg += "Group_Name: $Group_Name`n" }

    $error_msg += "Error: $ErrorMessage`n"
    $error_msg | Out-File -Append -FilePath $LogFilePath
}

function Get-All-Groups {
    param ()
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    try {
        $response = Invoke-RestMethod ('https://cloudsense.atlassian.net/wiki/rest/api/group') -Method 'GET' -Authentication Basic -Credential $Auth -Headers $headers
    }
    catch {
        $error_msg += $_.Exception.Message + "`n"
        $error_msg | Out-File -Append -FilePath $logFilePath
    }
    
    $groups = @()
    While (-not ([string]::IsNullOrEmpty($response._links.next))) {
        $groups += $response.results
        $response = Invoke-RestMethod -Method Get -Uri $response._links.next -Headers $headers        
    } 
    $groups += $response.results
    try {
        $AllGroups = $groups | Where-Object { $_.name -ne "all users from g suite" }
    }
    catch {
        $error_msg = 'Get-All-Groups function, Failed to remove "all users from g suite"' + "`n"
        $error_msg += $_.Exception.Message + "`n"
        $error_msg | Out-File -Append -FilePath $logFilePath
    }
    return $AllGroups;
}

function Get-Users {
    param ()
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $atlassian_token")
    try {
        $response = Invoke-RestMethod -Method Get -Uri('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/users') -Headers $headers
        While (-not ([string]::IsNullOrEmpty($response.links.next))) {
            $users += $response.data
            $response = Invoke-RestMethod -Method Get -Uri($response.links.next) -Headers $headers        
        } 
        $users += $response.data  
    }
    catch {
        Log-Error -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    return $users
}

function Get-User {
    param (
        $User_Email
    )
    return $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email }
}

function Get-User-Groups {
    param (
        $User_Email
    )
    $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email } 
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    try {
        $response = Invoke-RestMethod -Method Get ('https://cloudsense.atlassian.net/wiki/rest/api/user/memberof?accountId=' + $user.account_Id ) -Authentication Basic -Credential $Auth -Headers $headers
        $groups = @()
        While ($null -ne ($response._links.next)) {
            $groups += $response.results
            $response = Invoke-RestMethod -Method Get -Uri($response._links.next) -Headers $headers        
        } 
        $groups += $response.results
        $AllGroups = $groups | Where-Object { $_.name -ne "all users from g suite" }
    }
    catch {
        Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    
    return $AllGroups
}
function Add-User-To-Group {
    param (
        $User_Email, $Group_Name
    )
    $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email }
    $AllGroups = Get-All-Groups
    $group = $AllGroups | Where-Object { $_.name -eq $Group_Name }

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"    
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $atlassian_token")
    $headers.Add("Content-Type", "application/json")
    $body = @"
    {
        `"account_id`": `"$($user.account_id)`"
    }
"@

    try {
        $result = Invoke-WebRequest ('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/directory/groups/' + $group.id + '/memberships') -Method 'POST' -Headers $headers -Body $body
    }
    catch {
        Log-Error -Group_Name $Group_Name -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath

    }
    return $result
}
function Check_User_Groups {
    param (
        $AllGroups, $userGroups, $curent_user, $user
    )
    if ($user.employmentType -eq "Contractor" -and $userGroups -notcontains "Contractor") {
        Add-User-To-Group -User_Email $curent_user.email -Group_Name "Contractor"
        return;
    }
    $AllGroups = Get-All-Groups
    $CurrentGroup = $curent_user.division
    $FunctionGroup = $($CurrentGroup + ' - ' + $curent_user.function) 

    $CurentUserLocation = $curent_user.location

    #User Location Groups
    if (-not [string]::IsNullOrEmpty($curent_user.location)) {
        if ($AllGroups.name -contains $CurentUserLocation -and $userGroups.name -contains $CurentUserLocation) {
            $NumberOfGroups = $userGroups | Where-Object { $_.name -in $AllLocations } 
            if ($NumberOfGroups.Count -gt 1) {      
                foreach ($group in $NumberOfGroups) {
                    RemoveUserFromGroup -User_Email $curent_user.email -Group_Name $group.name
                }
                Add-User-To-Group -User_Email $curent_user.email -Group_Name $CurentUserLocation
            }
        }
        elseif ($AllGroups.name -notcontains $CurentUserLocation){
            Create-Group -Group_Name $CurentUserLocation -Group_Description "Curent User Location"
            Start-Sleep -s 15
            Add-User-To-Group -User_Email $curent_user.email -Group_Name $CurentUserLocation
        }
        elseif ($userGroups.name -notcontains $CurentUserLocation) {
            Add-User-To-Group -User_Email $curent_user.email -Group_Name $CurentUserLocation
        }
    }


    if (-not [string]::IsNullOrEmpty($curent_user.function)) {
        #Check if the user perhaps changed the function -> remove the old one and put the new one
        if ($AllGroups.name -contains $FunctionGroup -and $userGroups.name -contains $FunctionGroup) {
            $NumberOfGroups = $userGroups | Where-Object { $_.name -in $AllFunctions } 
            if ($NumberOfGroups.Count -gt 1) {      
                foreach ($group in $NumberOfGroups) {
                    RemoveUserFromGroup -User_Email $curent_user.email -Group_Name $group.name
                }
                Add-User-To-Group -User_Email $curent_user.email -Group_Name $FunctionGroup
            }
        }

        #Checks if user function group is among all groups
        elseif ($AllGroups.name -notcontains $FunctionGroup) {
            #If it isn't -> create it
            Create-Group -Group_Name $FunctionGroup -Group_Description $("CS division: " + $CurrentGroup + " - function: " + $curent_user.function)
            Start-Sleep -s 15
            Add-User-To-Group -User_Email $curent_user.email -Group_Name $FunctionGroup
        }
        #Check if the user is in that group. If not -> add them
        elseif ($userGroups.name -notcontains $FunctionGroup) {
            Add-User-To-Group -User_Email $curent_user.email -Group_Name $FunctionGroup
        }
    }
            

    # If "all-groups" contain a group with the name of the user's current division, and the user is in that group
    if ($AllGroups.name -contains $CurrentGroup -and $userGroups.name -contains $CurrentGroup) {
        $NumberOfGroups = $userGroups | Where-Object { $_.name -in $AllDivisions } 
        # User is in multiple division groups. Remove them all and put them in the one that corresponds to their division.
        # User changed division
        if ($NumberOfGroups.Count -gt 1) {
            foreach ($group in $NumberOfGroups) {
                RemoveUserFromGroup -User_Email $curent_user.email -Group_Name $group.name
            }
            Add-User-To-Group -User_Email $curent_user.email -Group_Name $curent_user.division
        }
    }

    # The user's division group does not exist at all, so it is created and the user is added inside
    elseif ($AllGroups.name -notcontains $CurrentGroup) {
        Create-Group -Group_Name $curent_user.division -Group_Description $("CS division: " + $curent_user.division) 
        $AllGroups = Get-All-Groups
        Add-User-To-Group -User_Email $curent_user.email -Group_Name $curent_user.division
    }
    # The user is not in the group corresponding to their current division
    elseif ($userGroups.name -notcontains $CurrentGroup) {
        Add-User-To-Group -User_Email $curent_user.email -Group_Name $curent_user.division
    }
            
    # Adding employees to the group "confluence-users" who don't already have it (excluding contractors)
    
    if ($userGroups.name -notcontains "confluence-users") {
        Add-User-To-Group -User_Email $curent_user.email -Group_Name "confluence-users"
    }  
    
    #Managing SLT, Managers, Team_Lead groups
    #SLT
    if ($curent_user.isSlt -and $userGroups.name -notcontains "SLT"){
        Add-User-To-Group -User_Email $curent_user.email -Group_Name "SLT"
    }
    elseif (-not $curent_user.isSlt -and $userGroups.name -contains "SLT") {
        RemoveUserFromGroup -User_Email $curent_user.email -Group_Name "SLT"
    }

    #Managers
    if ($curent_user.isManager -and $userGroups.name -notcontains "Managers"){
        Add-User-To-Group -User_Email $curent_user.email -Group_Name "Managers"
    }
    elseif (-not $curent_user.isManager -and $userGroups.name -contains "Managers") {
        RemoveUserFromGroup -User_Email $curent_user.email -Group_Name "Managers"
    }

    #Team Lead  
    if ($curent_user.isTeamLead -and $userGroups.name -notcontains "Team Lead"){
        Add-User-To-Group -User_Email $curent_user.email -Group_Name "Team Lead"
    }
    elseif (-not $curent_user.isTeamLead -and $userGroups.name -contains "Team Lead") {
        RemoveUserFromGroup -User_Email $curent_user.email -Group_Name "Team Lead"
    }
}

function Remove-User-From-Groups {
    param (
        $User_Email
    )
    try {
        $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email } 
        $response = Get-User-Groups -User_Email $User_Email 
    }
    catch {
        Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $atlassian_token")

    for ($i = 0; $i -lt $response.length; $i++) {
        try {
            $result = Invoke-WebRequest -Method Delete -Uri ('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/directory/groups/' + $response[$i].id + '/memberships/' + $User.account_ID) -Headers $headers
        }
        catch {
            Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        }        
    }
}

function RemoveUserFromGroup {
    param ( 
        $User_Email, $Group_Name 
    )
    try {
        $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email } 
        $response = Get-User-Groups -User_Email $User_Email 

        $group = $response | Where-Object { $_.name -eq $Group_Name }

        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $atlassian_token")

        $result = Invoke-WebRequest -Method Delete -Uri ('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/directory/groups/' + $group.id + '/memberships/' + $User.account_ID) -Headers $headers

    }
    catch {
        Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath

    }
}

function Create-Group {
    param (
        [Parameter(Mandatory = $true)][string]$Group_Name,
        [Parameter(Mandatory = $false)][string]$Group_Description
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $atlassian_token")

    $body = @"
    {
        `"name`": `"$Group_Name`",
        `"description`": `"$Group_Description`"
    }
"@
    try {
        $response = Invoke-RestMethod ('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/directory/groups') -Method 'POST' -Headers $headers -Body $body
        $response | ConvertTo-Json
    }
    catch {
        Log-Error -Group_Name $Group_Name -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }    
    return $response
}
function Delete-Group {
    param (
        $Group_Name
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $atlassian_token")
    $headers.Add("Accept", "application/json") 
    $Group = Get-Groups | Where-Object { $_.name -eq $Group_Name }
    Write-Host $Group.id
    try {
        $result = Invoke-WebRequest -Method Delete -Uri ('https://api.atlassian.com/admin/v1/orgs/' + $atlassian_id + '/directory/groups/' + $Group.id) -Headers $headers 
    }
    catch {
        Log-Error -Group_Name $Group_Name -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    return $result
}

function SuspendUserAccess {
    param (
        $User_Email
    )
    $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email }
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $atlassian_token")
    $headers.Add("Accept", "application/json")
    try {
        Invoke-WebRequest -Method Post -Uri ('https://api.atlassian.com/admin/v1/orgs/' + $OrgId + '/directory/users/' + $user.account_id + '/suspend-access') -Headers $headers -ContentType 'application/json'
    }
    catch {
        Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
}

function Delete-User {
    param (
        $User_Email
    )  
    $user = $AllConfluenceUsers | Where-Object { $_.email -eq $User_Email }
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Bearer $atlassian_token")
    try {
        Invoke-WebRequest -Method Post -Uri ('https://api.atlassian.com/users/' + $user.account_id + '/manage/lifecycle/delete') -Headers $headers -ContentType 'application/json'
    }
    catch {
        Log-Error -User_Email $User_Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
}

$Bamboo_users = Import-Clixml -Path '.\AllUsersBamboo.xml'
$Inactive_users = Import-Clixml -Path '.\TerminatedUsersBamboo.xml'

foreach ($inactiveUser in $Inactive_users){
    SuspendUserAccess -User_Email $inactiveUser.email
    Remove-User-From-Groups -User_Email $inactiveUser.email
}

$AllConfluenceUsers = Get-Users
$totalRecords = $AllConfluenceUsers.Count

$AllDivisions = $Bamboo_users | Where-Object { $_.status -eq "Active" } | Select-Object -ExpandProperty division -Unique
$AllFunctions = $Bamboo_users | Where-Object { $_.status -eq "Active" } | Select-Object -ExpandProperty function -Unique

$AllLocations = $Bamboo_users | Where-Object { $_.status -eq "Active" } | Select-Object -ExpandProperty location -Unique

$i = 0 
$activity = "Processing Users"
$AllGroups = Get-All-Groups

foreach ($user in $AllConfluenceUsers) {
    $i++
    $curent_user = $Bamboo_users | Where-Object { $_.email -eq $user.email }
    if ($curent_user -eq $null) {
        continue;
    }
    $userGroups = Get-User-Groups -User_Email $curent_user.email
    if ($userGroups.Count -gt 20) {
        Write-Host "User ima više od 20 grupa :" + $user.email
        continue;
    }
    switch ($curent_user.status) {
        "Inactive" {
            break
        }
        "Active" {
            Check_User_Groups -AllGroups $AllGroups -userGroups $userGroups -curent_user $curent_user -user $user
        }
    }

    $percentComplete = [math]::Round(($i / $totalRecords) * 100)
    Write-Progress -Activity $activity -PercentComplete $percentComplete
}

Write-Progress -Activity $activity -Status "Processing completed." -Completed

