$login_url = "your_login_url"

function GetAccessToken {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")
    $body = "grant_type=password&client_id=3MVG99OxTyEMCQ3hvWMuh50J_qRehBz69UPi2xAlxBWqHjMi1cdYYrEOZbWetFWRJeNuaLKVTY0UDhRoMPYe3&client_secret=821DE2EFF653A0AEF86497C99D61501D6401A42DE60C05DA7F71EBB170609F92&username=din.sadovic%40cloudsense.com&password=Zagreb2004ARF1zz7YJ8kUzLwCzYlqDCV0K"
    #get variables out of this req and save them as global variables / variables that are used in gitlab
    $response = Invoke-RestMethod 'your_login_url/services/oauth2/token' -Method 'POST' -Headers $headers -Body $body
    return $response.access_token
}

$Access_Token = GetAccessToken

function Get-Users {
    param (
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)
    $response = Invoke-RestMethod ($login_url + 'services/data/v59.0/queryAll/?q=SELECT id,KimbleOne__EndDate__c,KimbleOne__User__r.FederationIdentifier,KimbleOne__ExternalId__c,KimbleOne__FirstName__c, KimbleOne__LastName__c,KimbleOne__ResourceManager__r.Name, KimbleOne__Contact__r.Email, KimbleOne__User__r.Email, KimbleOne__BusinessUnit__r.Name, KimbleOne__Location__r.Name, KimbleOne__Calendar__r.Name, KimbleOne__StandardRevenueCurrencyISOCode__c, KimbleOne__ExpenseReimbursementCurrencyIsoCode__c, KimbleOne__ResourceType__r.Name, KimbleOne__StartDate__c, KimbleOne__BusinessUnitGroup__r.Name, KimbleOne__BusinessUnitSecondary__r.Name, KimbleOne__TimePattern__r.Name, KimbleOne__TimePatternVariant__r.Name, KimbleOne__Grade__r.Name, KimbleOne__ActivityRole__r.Name, Name, CurrencyIsoCode FROM KimbleOne__Resource__c WHERE KimbleOne__User__c != NULL') -Method 'GET' -Headers $headers

    return $response.records
}

function Update_user {
    param (
        $Bamboo_user, $curent_Kimble_User
    )
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer " + $Access_Token)

    $body = @{
        KimbleId               = $curent_Kimble_User.KimbleId
        currency               = $curent_Kimble_User.currency
        expensecurrency        = $curent_Kimble_User.expensecurrency
        calendar               = $curent_Kimble_User.calendar
        user                   = $curent_Kimble_User.FederationId
        firstname              = $Bamboo_user.firstname
        lastname               = $Bamboo_user.lastname
        location               = $curent_Kimble_User.location
        type                   = $curent_Kimble_User.type
        startdate              = $curent_Kimble_User.startdate
        businessunitgroup      = $curent_Kimble_User.businessunitgroup
        timepattern            = $curent_Kimble_User.timepattern
        timepatternvariant     = $curent_Kimble_User.timepatternvariant
        grade                  = $Bamboo_user.grade
        resourcename           = $curent_Kimble_User.resourcename
        primaryrole            = $curent_Kimble_User.function
        contact                = $curent_Kimble_User.contact
        currencyisocode        = $curent_Kimble_User.currencyisocode
        businessunitsecondary  = $curent_Kimble_User.businessunitsecondary
        bu                     = $curent_Kimble_User.entity
        EmployeeId             = $Bamboo_user.employeeId
    }

    if ($curent_Kimble_User.grade -ne $Bamboo_user.grade) {
        $body.effectiveDate = [System.DateTime]::Parse($Bamboo_user.effectiveDateGradeFunction).ToString("dd/MM/yyyy")
    }

    $jsonBody = $body | ConvertTo-Json -Compress

    $response = Invoke-RestMethod 'your_login_url/services/apexrest/KimbleOne/v1.0/Import/ResourceImport' -Method 'POST' -Headers $headers -Body $jsonBody
    $response | ConvertTo-Json
    return $response
}


$Bamboo = Import-Clixml -Path '.\AllUsersBamboo.xml'

$Kimbleusers = Get-Users

$Kimbleusers | foreach { $_.KimbleOne__User__r.Email = $_.KimbleOne__User__r.Email -replace ".invalid","" }
$Kimbleusers | foreach { $_.KimbleOne__User__r.Email = $_.KimbleOne__User__r.Email -replace "cloudsensesolutions.com","cloudsense.com" }
$Kimbleusers | foreach { $_.KimbleOne__User__r.Email = $_.KimbleOne__User__r.Email -replace "cloudsensesolutions.invalidd","cloudsense.com" }


$entityMapping = @{
    "CloudSense d.o.o."             = "CloudSense d.o.o."
    "CloudSense Inc."               = "CloudSense Inc."
    "CloudSense Ltd."               = "CloudSense Ltd."
    "CloudSense Pty. Ltd."          = "CloudSense Pty."
    "CloudSense Software Pvt Ltd"   = "CloudSense Pvt. Ltd."
    "CloudSense Pte. Ltd."          = "CloudSense Singapore"
}

$Bamboo_users = $Bamboo | ForEach-Object {
    $currentEntity = $_.entity
    foreach ($key in $entityMapping.Keys) {
        if ($currentEntity -match [regex]::Escape($key)) {
            $_.entity = $entityMapping[$key]
            break 
        }
    }
    $_  
}

$MapedResurceUsers = $Kimbleusers | ForEach-Object {
    [PSCustomObject]@{
        FederationId = $_.KimbleOne__User__r.FederationIdentifier
        firstname = $_.KimbleOne__FirstName__c
        lastname = $_.KimbleOne__LastName__c
        resourcename = $_.Name
        contact = $_.KimbleOne__Contact__r.Email
        email = $_.KimbleOne__User__r.Email
        entity = $_.KimbleOne__BusinessUnit__r.Name
        location = $_.KimbleOne__Location__r.Name
        calendar = $_.KimbleOne__Calendar__r.Name
        currency = $_.KimbleOne__StandardRevenueCurrencyISOCode__c
        expensecurrency = $_.KimbleOne__ExpenseReimbursementCurrencyIsoCode__c
        type = $_.KimbleOne__ResourceType__r.Name
        startdate = $_.KimbleOne__StartDate__c
        businessunitgroup = $_.KimbleOne__BusinessUnitGroup__r.Name
        businessunitsecondary = $_.KimbleOne__BusinessUnitSecondary__r.Name
        timepattern = $_.KimbleOne__TimePattern__r.Name
        timepatternvariant = $_.KimbleOne__TimePatternVariant__r.Name
        grade = $_.KimbleOne__Grade__r.Name
        function = $_.KimbleOne__ActivityRole__r.Name
        currencyisocode = $_.CurrencyIsoCode
        KimbleId = $_.id
        EmployeeId = $_.KimbleOne__ExternalId__c
        enddate = $_.KimbleOne__EndDate__c
    }
}

foreach ($CurentBamboouser in $Bamboo_users){
    if ($CurentBamboouser.email -eq $null -or $CurentBamboouser.status -eq 'Inactive'){
        continue
    }
    $curent_Kimble_User =  $MapedResurceUsers | Where-Object {$_.FederationId -eq $CurentBamboouser.uuid}
    if ($curent_Kimble_User -eq $null){
        Write-Host "User nema kimble: $($CurentBamboouser.email)"
        continue
    }
    else {
        $differences = Compare-Object -ReferenceObject $CurentBamboouser -DifferenceObject $curent_Kimble_User -Property FirstName,LastName,email,entity,grade,EmployeeId
        if ($differences -ne $null){
            Write-Host "Treba napravit promjenu: $($CurentBamboouser.email)" 
            Update_user -Bamboo_user $CurentBamboouser -curent_Kimble_User $curent_Kimble_User
        }
    }
}