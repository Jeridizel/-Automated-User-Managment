#Parameters: First Name, Last Name, Email, Department, Division, Manager email, UUID, 

Set-PSRepository PSGallery -InstallationPolicy Trusted
Add-Type -AssemblyName 'System.Web'

if (-not (Get-Module Microsoft.Graph.Authentication -ListAvailable)) {
    Find-module Microsoft.Graph.Authentication | Install-Module -SkipPublisherCheck:$true -Force -Confirm:$false
    Find-Module Microsoft.Graph.Users | Install-Module -SkipPublisherCheck:$true -Force -Confirm:$false
    Find-Module Microsoft.Graph.Applications | Install-Module -SkipPublisherCheck:$true -Force -Confirm:$false
}

$ClientId = ""
$ClientSecretCredential = New-Object System.Management.Automation.PSCredential ($ClientId,(ConvertTo-SecureString -AsPlainText "a3S8Q~yyHwuFJOPojRfh6r-NGiE.Nf3wFPD1Canm"))
$TeanantId = ""

function Invoke-Authorization {
    try {
        Connect-MgGraph -TenantId $TeanantId -ClientSecretCredential $ClientSecretCredential -NoWelcome
        return 0
    }
    catch {
        Write-Output "Cannot authorize MgGraph API"
        return 1
    }
}

Invoke-Authorization

function Get-AllUsers {
    param ()

    return Get-MgUser -All  -Property Id,GivenName,Surname,DisplayName,CompanyName,Department,BusinessPhones,jobTitle,UserPrincipalName,MailNickname,Mail,EmployeeId,EmployeeHireDate
}

function Get-User {
    param (
        $employeeId
    )
    if ($null -eq $employeeId){
        return;
    }
    $User = Get-MGUser -Filter "employeeId eq '$employeeId'" -All -Property Id,GivenName,Surname,BusinessPhones,DisplayName,CompanyName,Department,MobilePhone,jobTitle,UserPrincipalName,MailNickname,Mail,EmployeeId,EmployeeHireDate

    return $User
}


function Generate-Password {
    param (
        $PWLength
    )

    $LowerA = [Char[]]"abcdefghjkmnpqrstuvwxyz"
    $UpperA = [Char[]]"ABCEFGHJKLMNPQRSTUVWXYZ"
    $Number = [Char[]]"2345679"
    $Spesial = [Char[]]"!@#$%"
    $n = [char[]]"1234"

    If ($PWLength -eq "") {
        $PWLength = 10
    }
    $Pass = ""
    For ($i = 1; $i -le $PWLength; $i++)
    {
        $r = $n | Get-Random -Count 1
        IF ($r -eq "1") {
            $Pass += $LowerA | Get-Random -Count 1
        }
        IF ($r -eq "2") {
            $Pass += $UpperA | Get-Random -Count 1
        }
        IF ($r -eq "3") {
            $Pass += $Number | Get-Random -Count 1
        }
        IF ($r -eq "4") {
            $Pass += $Spesial | Get-Random -Count 1
        }
    }
    return $Pass
}

function New-User {
    param (
        $CurentUser
    )    

    $PasswordProfile = @{ Password = $(Generate-Password -PWLength 10) }

    $new = New-MgUser -GivenName $CurentUser.firstName -Surname $CurentUser.lastName  `
        -CompanyName $CurentUser.entity `
        -DisplayName ($CurentUser.firstName + " " + $CurentUser.lastName) `
        -AccountEnabled:$true `
        -Mail $CurentUser.email `
        -UserPrincipalName $CurentUser.email `
        -MailNickname $CurentUser.email.Split("@")[0] `
        -PasswordProfile $PasswordProfile

    if ($null -ne $new) {
        #Send-Email -Email $CurentUser.email -Password $password #složit ovu funkciju
        Write-Output "Novi user kreiran: " + $CurentUser.email
        $Manager = Get-User -employeeId $(($Bamboo_users | Where-Object {$_.email -eq $CurentUser.managerEmail}).employeeId)
        $params = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($Manager.id)"
        }
        if ($null -eq $Manager){
            continue;
        }
        else{
            Set-MgUserManagerByRef -UserId $new.id -BodyParameter $params
        }
        return 0
    }
    else {
        return 1
    }
}

function Edit-User {
    param (
        $CurentBambooUser, $MicrosoftUser
    )

    $Manager = Get-User -employeeId $(($Bamboo_users | Where-Object {$_.email -eq $CurentBambooUser.managerEmail}).employeeId)

    Update-MgUser -UserId $MicrosoftUser.MicrosoftId -GivenName $CurentBambooUser.firstname `
        -Surname $CurentBambooUser.lastname `
        -CompanyName $CurentBambooUser.entity `
        -DisplayName ($CurentBambooUser.firstName + " " + $CurentBambooUser.lastName) `
        -Mail $CurentBambooUser.email `
        -UserPrincipalName $CurentBambooUser.email `
        -MailNickname $CurentBambooUser.email.Split("@")[0] `
        -JobTitle $CurentBambooUser.jobTitle `
        -Department $CurentBambooUser.department `
        -EmployeeId $CurentBambooUser.employeeId `
        -EmployeeHireDate $((Get-date $CurentBambooUser.hireDate -AsUTC))

    $params = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($Manager.id)"
    }
    if ($Manager -eq $null){
        continue;
    }
    else{
        Set-MgUserManagerByRef -UserId $MicrosoftUser.MicrosoftId -BodyParameter $params
    }

    Write-Output "Edit user: " + $CurentBambooUser.email
}

function Delete-User {
    param (
        $MicrosoftUser
    )
    $SuccessCheck = Remove-MgUser -UserId $MicrosoftUser.MicrosoftId  -PassThru
    Write-Host "deaktiviran / obrisan user: " + $MicrosoftUser.email
}

$AllMicrosoftUsers = Get-AllUsers

$AllMicrosoftUsers = $AllMicrosoftUsers | Where-Object {$_.UserPrincipalName -like "*@cloudsense.com"}

$MapedMicrosoftUsers = $AllMicrosoftUsers | ForEach-Object {
    [PSCustomObject]@{
        MicrosoftId       = $_.Id
        employeeId        = $_.EmployeeId
        firstname         = $_.GivenName
        lastname          = $_.Surname
        entity            = $_.CompanyName
        email             = $_.UserPrincipalName
        hireDate          = $_.EmployeeHireDate 
        jobTitle          = $_.jobTitle
        department        = $_.department
        workPhone         = $_.BusinessPhones
    }
}

$Bamboo_users = Import-Clixml -Path '.\AllUsersBamboo.xml'
$today = Get-Date

#Deleting / deactivating users
foreach ($user in $Bamboo_users) {
    $checkIfExists = $MapedMicrosoftUsers | Where-Object { $_.employeeId -eq $user.employeeId -or $_.email -eq $user.email }
    if ($user.status -eq "Inactive" -and $checkIfExists -ne $null){
        Delete-User -MicrosoftUser $checkIfExists
    }
}

#Creating new
$New_users = Import-Clixml -Path '.\NewUsersBamboo.xml'
foreach ($user in $New_users) {
    $checkIfExists = $MapedMicrosoftUsers | Where-Object { $_.employeeId -eq $user.employeeId -or $_.email -eq $user.email }
    if ($checkIfExists -eq $null){
        New-User -CurentUser $user
    }
}

#Updating 
Foreach ($user in $Bamboo_users){
    if ($user.status -eq "Inactive"){
        continue;
    }
    else {
        $checkIfExists = $null
        $checkIfExists = $MapedMicrosoftUsers | Where-Object { $_.employeeId -eq $user.employeeId -or $_.email -eq $user.email }
        if ($null -ne $checkIfExists){
            $differences = Compare-Object -ReferenceObject $user -DifferenceObject $checkIfExists -Property employeeId, firstname, lastname, entity, email,hireDate,jobTitle,department
            if ($differences -and $user.hireDate -le $today){
                Edit-User -CurentBambooUser $user -MicrosoftUser $checkIfExists
            }
            continue;
        }
        elseif ($user.status -eq "Active" -and $user.email -ne $null){
            continue;
        }
    }
}



