$ApiKey = ''

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFileName = "miradore.log"
$LogFilePath = Join-Path -Path $ScriptDir -ChildPath $LogFileName

$UserDataFileName = "UserData.log"
$InactiveUserDataFilePath = Join-Path -Path $ScriptDir -ChildPath $UserDataFileName

$UsersThatDontHaveMiradoreFileName = "UsersThatDontHaveMiradoreFileName.log"
$UsersThatDontHaveMiradoreFilePath = Join-Path -Path $ScriptDir -ChildPath $UsersThatDontHaveMiradoreFileName
function Log-Error {
    param(
        [string]$ScriptName,
        [int]$LineNumber,
        [string]$ErrorMessage,
        [string]$LogFilePath,

        [string]$Email_of_User = "",
        [string]$Serial_Number = "",
        [string]$Firstname = "",
        [string]$Lastname = "",
        [string]$Old_email = ""
    )
    $error_msg = "Script: $ScriptName`n"
    $error_msg += "Line: $LineNumber`n"

    if ($Email_of_User) { $error_msg += "Email_of_User: $Email_of_User`n" }
    if ($Serial_Number) { $error_msg += "Serial_Number: $Serial_Number`n" }
    if ($Firstname) { $error_msg += "Firstname: $Firstname`n" }
    if ($Lastname) { $error_msg += "Last Name: $Lastname`n" }
    if ($Old_email) { $error_msg += "Old_email: $Old_email`n" }

    $error_msg += "Error: $ErrorMessage`n"
    $error_msg | Out-File -Append -FilePath $LogFilePath
}

function Get-Users {
    param ()
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/User/?auth=' + $ApiKey + '&options=rows=1000,page=1&select=Email,Firstname,Lastname') -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)
        $allusers = $x.Content.Items.ChildNodes
    }
    catch {
        Log-Error -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    $filteredUsers = $allusers | Where-Object {$_.email -like "*@cloudsense.com"}
    return $filteredUsers 
}

function Get-User {
    param (
        $email
    )
    try {
        $allusers = Get-Users
    }
    catch {
        Log-Error -Email_of_User $email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    
    return $user = $allusers | Where-Object { $_.email -eq $email }
}

function Get-User-Devices {
    param (
        $email_of_user
    )
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/Device/?auth=' + $ApiKey + '&select=InvDevice.Model,InvDevice.DeviceType,InvDevice.SerialNumber,Enrollment.Completed&filters=User.Email%20eq%20' + $email_of_user) -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)

        $data = @()

        $x.SelectNodes('//InvDevice') | ForEach-Object {
            $deviceData = New-Object -TypeName PSObject
            $_.ChildNodes | ForEach-Object {
                $deviceData | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.'#text' -Force
            }

            $enrollmentNode = $_.NextSibling
            $enrollmentData = New-Object -TypeName PSObject
            $enrollmentNode.ChildNodes | ForEach-Object {
                $enrollmentData | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.'#text' -Force
            }

            $deviceData | Add-Member -MemberType NoteProperty -Name 'Enrollment' -Value $enrollmentData
            $data += $deviceData
        }
    }
    catch {
        Log-Error -Email_of_User $email_of_user -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
    }
    return $data
}

function Wipe-Devices {
    param (
        $email_of_user
    )
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/Device/?auth=' + $ApiKey + '&select=ID&filters=User.Email%20eq%20' + $email_of_user) -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)
        $id = $x.Content.Items.ChildNodes.ID
        ForEach ($item in $id) {
            $response = Invoke-WebRequest -Method Post -Uri ('https://online.miradore.com/cloudsense1/api/v2/Device/' + $item + '?auth=' + $ApiKey)
        }
        return 0
    }
    catch {
        Log-Error -Email_of_User $email_of_user -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        return 1
    }
}

function Wipe-Device {
    param (
        $serial_number
    )
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/Device/?auth=' + $ApiKey + '&select=ID&filters=InvDevice.SerialNumber%20eq%20' + $serial_number) -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)
        $id = $x.Content.Items.ChildNodes.ID

        $response = Invoke-WebRequest -Method Post -Uri ('https://online.miradore.com/cloudsense1/api/v2/Device/' + $id + '?auth=' + $ApiKey) 
        return 0    #successful
    } 
    catch {
        Log-Error -Serial_Number $serial_number -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        return 1   #failed
    }
    
    
}

function New-User {
    param (
        $firstname, $lastname, $email, $phoneNumber
    )
    try {
        $response = Invoke-WebRequest -Method Post -Uri ('https://online.miradore.com/cloudsense1/API/User?auth=' + $ApiKey) -ContentType "aplication/xml" -Body `
            @"
<Content>
    <Items>
        <User>
            <Email>$Email</Email>
            <Firstname>$Firstname</Firstname>
            <Lastname>$Lastname</Lastname>
            <PhoneNumber>$phoneNumber</PhoneNumber>
        </User>
    </Items>
</Content>
"@
        return 0    #successful
    }
    catch {
        Log-Error -Firstname $firstname -Lastname $lastname -Email_of_User $email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        return 1
    }
}

function Edit-User {
    param (
        $old_email, $new_email, $new_first_name, $new_last_name, $new_phoneNumber
    )
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/User/?auth=' + $ApiKey + '&select=ID&filters=Email%20eq%20' + $old_email) -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)
        $id = $x.Content.Items.ChildNodes.ID
        if ([string]::IsNullOrEmpty($new_email)) {
            $new_email = $old_email
        }
        # when api allows make to that user email can be updated
        $response = Invoke-WebRequest -Method Put -Uri ('https://online.miradore.com/cloudsense1/API/User/' + $id + '?auth=' + $ApiKey) -ContentType "aplication/xml" -Body `
@"
<Content>
    <Items>
        <User>
            <Firstname>$new_first_name</Firstname>
            <Lastname>$new_last_name</Lastname>
            <Middle></Middle>
            $(([string]::IsNullOrEmpty($new_phoneNumber)) ? "<PhoneNumber></PhoneNumber>" : "<PhoneNumber>$new_phoneNumber</PhoneNumber>")
            </User>
    </Items>
</Content>
"@
        return 0
    }
    catch {
        Log-Error -Firstname $new_first_name -Lastname $new_last_name -Old_email $old_email -Email_of_User $new_email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        return 1
    }
}

function Delete-User {
    param (
        $Email
    )
    try {
        $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/User/?auth=' + $ApiKey + '&select=ID&filters=Email%20eq%20' + $Email) -Headers @{"accept" = "application/xml" }
        [xml]$x = New-Object -TypeName System.Xml.XmlDocument
        $x.LoadXml($response.Content)
        $id = $x.Content.Items.ChildNodes.ID
        $result = Invoke-WebRequest -Method Delete -Uri ('https://online.miradore.com/cloudsense1/API/User/' + $id + '?auth=' + $ApiKey)

        return 0
    }
    catch {
        Log-Error -Email_of_User $Email -ScriptName $MyInvocation.ScriptName -LineNumber $MyInvocation.ScriptLineNumber -ErrorMessage $_.Exception.Message -LogFilePath $logFilePath
        return 1
    }
}

function Get-NumberOfUserDevices {
    param (
        $User_Email
    )
    $response = Invoke-WebRequest -Method Get -Uri ('https://online.miradore.com/cloudsense1/API/Device/?auth=' + $ApiKey + '&select=ID,OnlineStatus&filters=OnlineStatus%20ne%20Unmanaged%20and%20User.Email%20eq%20' + $User_Email) -Headers @{"accept" = "application/xml" }
    [xml]$x = New-Object -TypeName System.Xml.XmlDocument
    $x.LoadXml($response.Content)
    $id = $x.Content.Items.ChildNodes.ID

    return $id.Count
}

function Inactive_user_data_logging {
    param (
       $UserEmail, $InactiveUserDataFilePath
    )
    
    $data = Get-User-Devices -email_of_user $UserEmail

    $UserEmail | Out-File -Append -FilePath $InactiveUserDataFilePath

    foreach ($device in $data){
        $msg = ""
        $msg = "Model: " + $device.Model + "`r`n"
        $msg+= "SerialNumber: " + $device.SerialNumber + "`r`n"
        $msg+= "Enrollment date: " + $device.Enrollment.Completed + "`r`n"
        $msg | Out-File -Append -FilePath $InactiveUserDataFilePath
    }
}

function SendEmail {
    param (
        $numberedUserList
    )
    # Set your client ID and client secret
    $client_id = ""
    $client_secret = ""
    $refresh_token = ""

    # Define the token request URL
    $token_url = ""

    # Define the request body
    $request_body = @{
        client_id = $client_id
        client_secret = $client_secret
        refresh_token = $refresh_token
        grant_type = "refresh_token"
    }

    # Make the POST request using Invoke-RestMethod and store the response in a variable
    $response = Invoke-RestMethod -Method Post -Uri $token_url -ContentType "application/x-www-form-urlencoded" -Body $request_body

    # Extract the access_token from the response
    $access_token = $response.access_token

    # Print the extracted access_token
    Write-Output "Access Token: $access_token"


    # Define the Gmail API URL and your authorization token
    $GMAIL_API_URL = 'https://www.googleapis.com/upload/gmail/v1/users/me/messages/send'
    $AUTH_TOKEN = "Bearer $access_token"

$emailContent = @"
From:  IT <your_email_here>
To: <who_you_sending_email>
Subject: Users that DON'T have Miradore installed
Content-type: text/html; charset=UTF-8

<html>
<p><span style="font-family:Arial,Helvetica,sans-serif"><span style="font-size:14px">User Information:</span></span></p>
<pre>$numberedUserList</pre>
<div style="color: #4a26ab; font-family: arial, helvetica, sans-serif; font-size: 14px;">
<br>
<strong>Din Sadovic</strong>
</div>
<div style="color: #484848; font-family: arial, helvetica, sans-serif; font-size: 12px;">
<strong>IT Technician</strong>
</div>
<div style="font-size: 12px; color: #484848; font-family: arial, helvetica, sans-serif;">
<br>
</div>
<div style="font-size: 12px; color: #484848; font-family: arial, helvetica, sans-serif;">
+385994720225   <br>
din.sadovic@cloudsense.com
</div>
<div style="font-size: 12px; color: #484848; font-family: arial, helvetica, sans-serif;">
<br>
<a href="https://www.cloudsense.com/?utm_medium=email&utm_campaign=SignatureLogo" target="_blank" style="font-size: 12px; font-family: arial, helvetica, sans-serif;">
    <img src="https://www.cloudsense.com/hubfs/Signature/CloudSenselogo.png" alt="CloudSense" height="37" width="106" style="border-style: none;">
</a>
</div>
<div style="font-family: arial, helvetica, sans-serif; color: #33333d; font-size: 10px;">
<br>
Registered office: Radnicka cesta 80, 15th floor, 10000 Zagreb, Croatia
</div>
<div style="font-family: arial, helvetica, sans-serif; color: #33333d;">
<br>
<a href="https://insight.cloudsense.com/signature/?utm_medium=email&utm_campaign=SignatureCampaign" target="_blank">
<img src="https://www.cloudsense.com/hubfs/Signature/Campaign.png?q=2" width="380" height="120" alt="Commerce and Subscriber Management"
    style="color:#4a26ab;font-family: helvetica; border-style: none;"></a>
<br><br>
</div>
</html>
"@

    Invoke-RestMethod -Uri $GMAIL_API_URL -Method Post -Headers @{
        'Authorization' = $AUTH_TOKEN
        'Content-Type' = 'message/rfc822'
    } -Body ([System.Text.Encoding]::UTF8.GetBytes($emailContent))

}


$UsersThatDontHaveMiradore = @()
$Bamboo_users = Import-Clixml -Path '.\AllUsersBamboo.xml'
$response = Get-Users

$MiradoreUsers = $response | ForEach-Object {
    $userEmail = $_.Email
    $numberOfDevices = Get-NumberOfUserDevices -User_Email $userEmail
    [PSCustomObject]@{
        Firstname         = $_.Firstname
        Lastname          = $_.Lastname
        Email             = $userEmail
        Number_of_devices = $numberOfDevices
    }
}

$ActiveBamboo = $Bamboo_users | Where-Object { $_.status -eq "Active" }
$differences = Compare-Object -ReferenceObject $MiradoreUsers -DifferenceObject $ActiveBamboo -Property Firstname, Lastname, Email | Where-Object {$_.SideIndicator -eq "=>"}
#Finding users with different email, first or last name and updates them
foreach ($user in $differences){
    $Bamboo_data = $Bamboo_users | Where-Object {$_.email -eq $user.Email}

    if ($MiradoreUsers -notcontains $Bamboo_data.Email){
        New-User -firstname $Bamboo_data.firstName -lastname $Bamboo_data.lastName -email $Bamboo_data.email -phoneNumber $Bamboo_data.workPhone
    }
    else{
        $result = Edit-User -old_email $user.Email -new_email $Bamboo_data.email -new_first_name $Bamboo_data.firstName -new_last_name $Bamboo_data.lastName
        if ($result -eq 0){
            Write-Host "Uspjesno updejtan: " + $Bamboo_data.email
        }
        elseif ($result -eq 1) {
            Write-Host "FAILED " + $Bamboo_data.email
        }
    }
}

#Deleting user accounts and wiping devices for inactive users, checking if person has miradore on their laptop or not
for ($i = 0; $i -lt $MiradoreUsers.COUNT; $i++) {
    $curent_user = $Bamboo_users | Where-Object { $_.email -eq $MiradoreUsers[$i].Email } 

    switch ($curent_user.status) {
        "Inactive" {
            Inactive_user_data_logging -UserEmail $MiradoreUsers[$i].Email -InactiveUserDataFilePath $InactiveUserDataFilePath
            Wipe-Devices -email_of_user $MiradoreUsers[$i].Email
            Delete-User -Email $MiradoreUsers[$i].Email
            #dati tag to-return 
        }
        "Active" {
            if ($MiradoreUsers[$i].Number_of_devices -eq 0) {
                $UsersThatDontHaveMiradore += $MiradoreUsers[$i].Email
                Write-Host $MiradoreUsers[$i].Email
            }
        }
    }
}

$UsersList = [System.Collections.Generic.List[Object]]$UsersThatDontHaveMiradore

#Removing contractors and people that have linux from "List of people who dont have miradore installed"
foreach ($user in $UsersThatDontHaveMiradore){
    $curent_user = $Bamboo_users | Where-Object {$_.email -eq $user}
    if ($curent_user.employmentType -eq "Contractor"){
        $UsersList.Remove($user)
    }
}
foreach ($emailToRemove in $UsersToRemove) {
    $UsersList.Remove($emailToRemove)
}

$UsersList | Out-File -Path $UsersThatDontHaveMiradoreFilePath

$numberedUserList = ""
$count = 1
foreach ($user in $UsersList) {
    $numberedUserList += "$count. $user`n"
    $count++
}

if ((get-Date -Format dddd).ToString() -like "Monday") {
    SendEmail -numberedUserList $numberedUserList
}








