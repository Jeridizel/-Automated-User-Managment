$login_url = "put_link_here"

function GetAccessToken {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")
    $body = "grant_type=password&client_id=your_password&clientDd_here3&client_secret=client_secret_here&username=username_here&password=password&SFsecuritytoken_here"
    $response = Invoke-RestMethod ($login_url + 'services/oauth2/token') -Method 'POST' -Headers $headers -Body $body
    return $response.access_token
}

$Access_Token = GetAccessToken

function Map_UserRole_to_RoleId {
    param(
        $UserRoleName
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/query/?q=SELECT UserRole.name, userroleid  from User where isactive = true and UserRoleId != ' + "''" + 'group by UserRole.name, userroleid ') -Method 'GET' -Headers $headers
    $response = $response.records 

    $x = $response | Where-Object {$_.Name -eq $UserRoleName}
    $UserRoleId += $x.UserRoleId
    
    return $UserRoleId
}

function Map_ProfileName_to_ProfileId {
    param(
        $ProfileName
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/query/?q=SELECT ProfileId, Profile.name FROM User Group by ProfileId, Profile.name ') -Method 'GET' -Headers $headers
    $response = $response.records

    $x = $response | Where-Object {$_.Name -eq $ProfileName}
    $ProfileId += $x.ProfileId
    
    return $ProfileId
}

function Get-Users {
    param (
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)
    $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/queryAll/?q=SELECT Id,FederationIdentifier,Firstname,Lastname,IsActive,Email,Start_Date__c,Department,Division,Title,Manager.Id,Manager.FederationIdentifier,CompanyName FROM User ORDER BY Name') -Method 'GET' -Headers $headers

    return $response.records
}

function Get-User {
    param (
        $Uuid
    )
    $response = Get-Users | Where-Object {$_.uuid -eq $Uuid}

    return $response

}

function Edit-User {
    param (
       $CurrentBamboUser, $curent_SF_user
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)
    $headers.Add("Cookie", "BrowserId=R_ixHENbEe-wp8kC_ARuQQ; CookieConsentPolicy=0:1; LSKey-c`$CookieConsentPolicy=0:1")

    $differences = Compare-Object -ReferenceObject $CurentBamboouser -DifferenceObject $curent_SF_user -Property Uuid,Firstname,LastName,Email,Department,Division,JobTitle,Entity

    $referenceValues = @{}
    $differenceValues = @{}

    $differences | ForEach-Object {
        if ($_.SideIndicator -eq '=>') {
            $referenceValues[$_.Uuid] = $_
        } elseif ($_.SideIndicator -eq '<=') {
            $differenceValues[$_.Uuid] = $_
        }
    }
    $preJsonBody = [PSCustomObject]@{
    }

    foreach ($uuid in $referenceValues.Keys) {
        $refObject = $referenceValues[$uuid]
        $diffObject = $differenceValues[$uuid]

        $properties = $refObject.PSObject.Properties.Name | Where-Object { $_ -ne 'SideIndicator'}
        foreach ($property in $properties) {
            if ($refObject.$property -ne $diffObject.$property) {

                switch ($property) {
                    "Uuid" { 
                        $preJsonBody | Add-Member NoteProperty -Name 'FederationIdentifier' -Value $diffObject.$property
                    }
                    "FirstName" {  
                        $preJsonBody | Add-Member NoteProperty -Name 'FirstName' -Value $diffObject.$property
                    }
                    "Lastname" {  
                        $preJsonBody | Add-Member NoteProperty -Name 'Lastname' -Value $diffObject.$property
                    }
                    "Department" {  
                        $preJsonBody | Add-Member NoteProperty -Name 'Department' -Value $diffObject.$property
                    }
                    "JobTitle" {  
                        $preJsonBody | Add-Member NoteProperty -Name 'Title' -Value $diffObject.$property
                    }
                    "Entity" {
                        if ($CurentBamboouser.employmentType -eq "Contractor") {
                            $preJsonBody | Add-Member NoteProperty -Name 'CompanyName' -Value "Contractor"
                        } else {
                            $preJsonBody | Add-Member NoteProperty -Name 'CompanyName' -Value $diffObject.$property
                        }  
                    }

                }
            }
        }
    }

    $currentManagerId = $curent_SF_user.ManagerId
    $managerSFUser = $MapedSalesforceUsers | Where-Object { $_.SalesforceId -eq $currentManagerId }
    $Bamboomanager = $BambooUsers | Where-Object { $_.email -eq $CurentBamboouser.managerEmail }

    if ($Bamboomanager.Uuid -ne $managerSFUser.Uuid) {
        $newManagerid = $MapedSalesforceUsers | Where-Object {$_.Uuid -eq $Bamboomanager.uuid}
        $preJsonBody | Add-Member NoteProperty -Name 'ManagerId' -Value $newManagerId.SalesforceId
    }

    if ($curent_SF_user.Entity -eq "Contractor" -and $CurentBamboouser.employmentType -eq "Contractor") {
        $preJsonBody.PSObject.Properties.Remove('CompanyName')
    }

    if (-Not [string]::IsNullOrEmpty($preJsonBody)){
        $jsonBody = $preJsonBody | ConvertTo-Json
$body = @"
    $jsonBody
"@

        $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/sobjects/User/' + $curent_SF_user.SalesforceId) -Method 'PATCH' -Headers $headers -Body $body
        Write-Host "User editan + $($CurentBamboouser.Email)"   
    }
}

function Deactivate-User {
    param (
        $curent_SF_user
    )
    $activeUser = $curent_SF_user | Where-Object {$_.IsActive -eq $true}
    if (-not $activeUser){
        return
    }
    $user_id = $activeUser.Id 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

$body = @"
{
	`"IsActive`": `"false`"
}
"@

    $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/User/' + $user_id) -Method 'PATCH' -Headers $headers -Body $body
}

function Map_PackageLicense.NamespacePrefix_to_PackageLicenseId {

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/query/?q=SELECT PackageLicenseId, PackageLicense.NamespacePrefix, COUNT(UserId) from UserPackageLicense group by PackageLicenseId, PackageLicense.NamespacePrefix') -Method 'GET' -Headers $headers
    $response = $response.records 

    return $response
}

function Add-License{ #Managed Packages
    param (
        $User_Email, $Bamboo_department
    )
    $response = Get-User -User_Email "$User_Email"
    $user_id = $response.Id 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)
     
    if ($Bamboo_department -eq "Customer Success"){
    $PackageLicense = Map_PackageLicense.NamespacePrefix_to_PackageLicenseId | Where-Object {$_.NamespacePrefix -eq "yoxel"}
     
$body = @"
{
    `"PackageLicenseId`": `"$($PackageLicense.PackageLicenseId)`"  
}
"@
    }

    elseif ($Bamboo_department -eq "Professional Services"){
        $PackageLicenseId = Map_PackageLicense.NamespacePrefix_to_PackageLicenseId | Where-Object {$_.NamespacePrefix -eq "KimbleOne"}
$body = @"
{
    `"PackageLicenseId`": `"$($PackageLicense.PackageLicenseId)`"  
}
"@

    }

    elseif ($Bamboo_department -eq "Sales"){
        
        $PackageLicense_NamespacePrefix = @()
        $PackageLicense_NamespacePrefix += "DMAPP_SOM"
        $PackageLicense_NamespacePrefix += "DMMAX"
        $PackageLicense_NamespacePrefix += "yoxel"
        $PackageLicense_NamespacePrefix += "ALTF"
    
        for ($i=0;$i -lt 4; $i++){
            $PackageLicenseId = Map_PackageLicense.NamespacePrefix_to_PackageLicenseId | Where-Object {$_.NamespacePrefix -eq "$($PackageLicense_NamespacePrefix[$i])"}
$body = @"
{
    `"PackageLicenseId`": `"$($PackageLicense.PackageLicenseId)`"  
}
"@
        if ($i -ne 3){
            $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/UserPackageLicense/' + $user_id) -Method 'PATCH' -Headers $headers -Body $body
        }
    }
    }

    # see if this works?? test on production not on prodmir

}

function Remove-License {
    param (
        $User_Email
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/query/?q=SELECT Id from UserPackageLicense WHERE User.Email = ''' + $User_Email + '''') -Method 'GET' -Headers $headers
    $response = $response.records

    foreach ($item in $response) {
        Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/UserPackageLicense/' + $($item.Id)) -Method 'DELETE' -Headers $headers
    }    
}

function Remove-PermissionSets {
    param (
        $User_Email
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/queryAll/?q=SELECT id FROM PermissionSetAssignment WHERE PermissionSetGroup.Id != '''' and Assignee.Email = ''' + $User_Email + '''') -Method GET -Headers $headers
    $response = $response.records

    foreach ($item in $response) {
        Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/PermissionSetAssignment/' + $($item.Id)) -Method 'DELETE' -Headers $headers
    }
}
function Map_PermissionSetGroup-DeveloperName_to_PermissionSetGroup-Id {
    param (
        $PermisionSetGroupNames
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + '/services/data/v59.0/query/?q=SELECT PermissionSetGroup.Id,PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE PermissionSetGroup.Id != '''' GROUP BY PermissionSetGroup.Id,PermissionSetGroup.DeveloperName') -Method 'GET' -Headers $headers
    $response = $response.records 
    $PermissionSetGroupIds = @()

    foreach ($groupName in $PermisionSetGroupNames) {
        $matchingGroup = $response | Where-Object { $_.DeveloperName -eq $groupName }

        if ($matchingGroup) {
            $PermissionSetGroupIds += $matchingGroup.Id
        }
    }
    $uniquePermissionSetGroupIds = $PermissionSetGroupIds | Select-Object -Unique
    
    return $uniquePermissionSetGroupIds
}

function Add-PermissionSet { #Permission Set Group Assignmentss
    param (
        $User_Email, $Function, $entity <#(location of firm)#>, $Division, $JobTitle
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $user_id = Get-User -User_Email "$User_Email" | Select-Object -ExpandProperty Id
    $PermisionSetGroupId = @()

    Switch ($Division) {
         "Engineering" {
            $PermisionSetGroupId += "Engineering"
            $PermisionSetGroupId += "R_D_Developer"
         }
         "Product & Content Marketing"{
            $PermisionSetGroupId += "Growth_Marketing"
         }
         "Business Development Representatives"{
            $PermisionSetGroupId += "Business_Development_Representatives"
         }
         "Product Support"{
            $PermisionSetGroupId += "Product_Support_CSP"
         }
         "Consulting - Delivery"{
            $PermisionSetGroupId += "Consulting_Delivery"
         }
         "Training"{
            $PermisionSetGroupId += "Training"
         }
         "Finance"{
            $PermisionSetGroupId += "Finance"
         }
         "Customer Success Management"{
            $PermisionSetGroupId += "Customer_Success_Management"
         }
         "Human Resources"{
            $PermisionSetGroupId += "Human_Resources"
         }
         "Recruitment" {
            $PermisionSetGroupId += "Recruitment"
         }
         "Alliances"{
            $PermisionSetGroupId += "Alliances"
         }
         "Legal" {
            $PermisionSetGroupId += "Legal"
         }
         "Office Management" {
            $PermisionSetGroupId += "Office_Management"
         }

    }
    switch ($entity) {
        "CloudSense d.o.o." {   #Croatia
            $PermisionSetGroupId += "CloudSenseCRO"
        }
        "CloudSense Software Pvt Ltd"{ #India
            $PermisionSetGroupId += "CloudSenseIND"
        }
    }
    switch -Wildcard ($JobTitle) {
        "DevOps Manager" {
            $PermisionSetGroupId += "Development_Manager"
        }
        "*Product Tester*" {
            $PermisionSetGroupId += "Engineering_Tester"
        }
        "*Customer Success Engineer*"{
            $PermisionSetGroupId += "Customer_Success_Engineering"
        }
        "FP&A Business Analyst"{
            $PermisionSetGroupId += "Senior_FPA_Business_Analyst"
        }
        "Assistant Management Accountan"{
            $PermisionSetGroupId += "Assistant_Management_Accountant"
        }
        "HR Business Partner" {
            $PermisionSetGroupId += "HR_Business_Partner_or_HR_Consultant"
        }
        "Acting HR Director"{
            $PermisionSetGroupId += "Head_of_HR_Shared_Services"
        }
        "Product_Architect"{
            $PermisionSetGroupId += "Product_Architect"
        }
        "Chief Business Solution Architect" {
            $PermisionSetGroupId += "Chief_Business_Solution_Architect"
        }
        "Head of Architecture and Technology" {
            $PermisionSetGroupId += "Head_of_Architecture_and_Technology"
        }
        "Associate Engineer"{
            $PermisionSetGroupId += "Associate_Engineer"
        }
        "Associate Engineer"{
            $PermisionSetGroupId += "Associate_Engineer"
        }
        "*Product_Developer*"{
            $PermisionSetGroupId += "Product_Developer"
        }
        "Head of Software Development - Europe"{
            $PermisionSetGroupId += "Engineering_Head_of_Software_Development_Europe"
        }
        "Principal Software Engineer"{
            $PermisionSetGroupId += "Engineering_Principal_Software_Engineer"
        }
        "Senior Software Engineer"{
            $PermisionSetGroupId += "Engineering_Senior_Software_Engineer"
        }
        "Software Engineer" {
            $PermisionSetGroupId += "Engineering_Software_Engineer"
        }
        "Graduate Engineer" {
            $PermisionSetGroupId += "Graduate_Engineer"
        }
        "Graduate Test Engineer"{
            $PermisionSetGroupId += "Graduate_Test_Engineer"
        }
        "Project Management Officer"{
            $PermisionSetGroupId += "Project_Management_Officer"
        }
        "VP Services"{
            $PermisionSetGroupId += "VP_Services"
        }
        "Solution Sales"{
            $PermisionSetGroupId += "Solution_Sales"
        }
        "Post-Implementation Software Developer" {
            $PermisionSetGroupId += "PostImplementation_Software_Developer"
        }
        "Junior Support Specialist" {
            $PermisionSetGroupId += "Junior_Support_Specialist"
        }
        "Graduate Product Support Engineer" {
            $PermisionSetGroupId += "Graduate_Associate"
        }
        
    }

    switch ($Function) {
        "Delivery Management" { 
            $PermisionSetGroupId += "Engineering_Delivery_Management"
         }
        
    }
    $PermisionSetGroupMaped = Map_PermissionSetGroup-DeveloperName_to_PermissionSetGroup-Id -PermisionSetGroupNames $PermisionSetGroupId

    foreach ($permissionId in $PermisionSetGroupMaped){
    $body = 
@"
{
    `"AssigneeId`": `"$user_id`",
    `"PermissionSetGroupId`": `"$permissionId`"
}   
"@

        $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/PermissionSetAssignment') -Method 'POST' -Headers $headers -Body $body
    }
}

function Reset_User_Password {
    param (
        $User_Email
    )
    $response = Get-User -User_Email $User_Email
    $user_id = $response.Id 

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/sobjects/User/' + $user_id + '/password') -Method 'DELETE' -Headers $headers
    Write-Host $response
}

$BambooUsers = Import-Clixml -Path '.\AllUsersBamboo.xml'

function Get_contacts {
    param (
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)
    $response = Invoke-RestMethod ($login_url + "services/data/v59.0/queryAll/?q=SELECT id,FirstName,LastName,Email,Account.Name FROM Contact WHERE Email LIKE '%cloudsen%' AND Account.Name != 'Cloudsense'") -Method 'GET' -Headers $headers

    return $response.records
}

function CheckManager {
    param (
        $curent_SF_user,$CurentBamboouser
    )
    $currentManagerId = $curent_SF_user.ManagerId
    $managerSFUser = $MapedSalesforceUsers | Where-Object { $_.SalesforceId -eq $currentManagerId }
    $Bamboomanager = $BambooUsers | Where-Object { $_.email -eq $CurentBamboouser.managerEmail }

    if ($Bamboomanager.Uuid -ne $managerSFUser.Uuid) {
        return $true
    }
    else {
        return $false    
    }
}

$all_users = Get-Users
$all_users | foreach { $_.email = $_.email -replace "cloudsensesolutions.com","cloudsense.com" }


$entityMapping = @{
    "CloudSense Ltd."               = "CloudSense Ltd."
    "CloudSense d.o.o."             = "CloudSense d.o.o."
    "CloudSense Software Pvt Ltd"   = "CloudSense Pvt. Ltd."
    "CloudSense Inc."               = "CloudSense Inc."
    "CloudSense Pty. Ltd."          = "CloudSense Pty."
    "CloudSense Pte. Ltd."          = "CloudSense Singapore"
}

$updatedBambooUsers = $bambooUsers | ForEach-Object {
    $currentEntity = $_.entity
    foreach ($key in $entityMapping.Keys) {
        if ($currentEntity -match [regex]::Escape($key)) {
            $_.entity = $entityMapping[$key]
            break 
        }
    }
    $_  
}

$MapedSalesforceUsers = $all_users | ForEach-Object {
    [PSCustomObject]@{
        SalesforceId      = $_.Id
        Uuid              = $_.FederationIdentifier
        Firstname         = $_.Firstname
        Lastname          = $_.Lastname
        Status            = $_.IsActive
        Email             = $_.Email
        HireDate          = $_.Start_Date__c
        Department        = $_.Department
        Division          = $_.Division
        JobTitle          = $_.Title
        ManagerId         = $_.Manager.Id
        Entity            = $_.CompanyName
    }
}

#deaktiviranje usera
$usersToDeactivate = Import-Clixml -Path '.\TerminatedUsersBamboo.xml'
foreach ($user in $usersToDeactivate){
    Deactivate-User -curent_SF_user $curent_SF_user
    Remove-PermissionSets -User_Email $curent_SF_user.Email
    Remove-License -User_Email $curent_SF_user.Email
    Write-Host "User deaktiviran: $($user.Email)"
}

#editiranje usera
foreach ($CurentBamboouser in $updatedBambooUsers) {
    $curent_SF_user = $MapedSalesforceUsers | Where-Object { $_.Uuid -eq $CurentBamboouser.uuid } | Select-Object -Unique

    if ($CurentBamboouser.status -eq "Inactive"){
        continue
    }
    if ($curent_SF_user -eq $null){
        Write-Host "User se nemoze nac na salesforcu: $($CurentBamboouser.email)"
        continue
    }
    else {
        $differences = Compare-Object -ReferenceObject $CurentBamboouser -DifferenceObject $curent_SF_user -Property  Uuid,Firstname,LastName,Email,Department,Division,JobTitle,Entity
        $ManagerChange = CheckManager -curent_SF_user $curent_SF_user -CurentBamboouser $CurentBamboouser
        if ($differences -ne $null -or $ManagerChange){
            Edit-User -CurrentBamboUser $CurentBamboouser -curent_SF_user $curent_SF_user
        }
    }
}
