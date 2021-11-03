#A script to find junior canvassers who have signed up for more than one shift in a day

$base_url = "https://api.getsling.com/v1"

Write-Output "Checking authentication..."
#Check if we already have an authentication token (mostly for repetitive testing)
If ($Auth) {
    #If there is one, try to use it
    Try {
        $SessionInfo = (Invoke-RestMethod -Method Get -Uri ($base_url + "/account/session") -Headers @{accept = "*/*"; Authorization = $auth})
    }
    Catch {
        #If we fail to use it, get a new one
        Write-Output "Need to authenticate"
        $username = Read-Host -Prompt "Username"
        $password = Read-Host -AsSecureString -Prompt "Password"
        
        $endpoint = "/account/login"
        $content = @{email = $username; password = (ConvertFrom-SecureString $password -AsPlainText).ToString()}
        $body = (ConvertTo-Json $content)
        $uri = $base_url + $endpoint

        $SessionInfo = (Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -ResponseHeadersVariable ResponseHeaders)
    }
}
Else {
    #If there's not authentication, we need to do that.
    Write-Output "Need to authenticate"
    $username = Read-Host -Prompt "Username"
    $password = Read-Host -AsSecureString -Prompt "Password"
    
    $endpoint = "/account/login"
    $content = @{email = $username; password = (ConvertFrom-SecureString $password -AsPlainText).ToString()}
    $body = (ConvertTo-Json $content)
    $uri = $base_url + $endpoint

    $SessionInfo = (Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -ResponseHeadersVariable ResponseHeaders)
}

#Display the username
Write-Output ("Authenticated as: " + $SessionInfo.user.name + " " + $SessionInfo.user.lastname)
$Authorization = $ResponseHeaders.Authorization

$userID = $SessionInfo.user.id
$orgID = $SessionInfo.org.id


#Prep the Authorization header
$Auth = ($Authorization.Replace("{","").Replace("}",""))
$headers = @{Authorization = $Auth; accept = "*/*"}

#Prep the Invoke-RequestMethod Paramaters for most things
$irqParams = @{
    uri = ""
    headers = $headers
    method = "Get"
    #StatusCodeVariable = $statusCode
    #ResponseHeadersVariable = $ResponseHeaders
}

Write-Output "Getting a list of users and groups..."
#Get a list of user and group data
$irqParams.uri = ($base_url + "/users/concise?user-fields=full")
$user_data = (Invoke-RestMethod @irqParams)
$users = $user_data.users
$groups = $user_data.groups

Write-Output "Determining which groups are actually locations..."
#Get a list of groups that are employee positions
$locations = @()
foreach ($group in ($groups | Get-Member | Where-Object {$_.MemberType -eq "NoteProperty"})) {
    If (($groups.($group.name).type) -eq "location") {
        $locations += $groups.($group.Name).id
    }
}

#Build Tomorrow in ISO8601 Time Duration
Write-Output "Building tomorrow..."
$tomorrowYear = (Get-Date).AddDays(1).Year
$tomorrowMonth = (Get-Date).AddDays(1).Month
$tomorrowDay = (Get-Date).AddDays(1).Day
$start = (Get-Date -Format "o" -Year $tomorrowYear -Month $tomorrowMonth -Day $tomorrowDay -Hour 0 -Minute 0 -Second 0 -Millisecond 0)
$end = (Get-Date -Format "o" -Year $tomorrowYear -Month $tomorrowMonth -Day $tomorrowDay -Hour 23 -Minute 59 -Second 59 -Millisecond 0)
$tommorrow = ("$start/$end")
$tommorrow = ("$start/PT24H")

#Get your calendar
Write-Output "Getting your calendar for tommorrow..."
$irqParams.uri = ($base_url + "/$orgID/calendar/$orgID/users/$userID`?dates="  + ([uri]::EscapeDataString($tommorrow)))
$calendar = (Invoke-RestMethod @irqParams)
Write-Output "Determining which calendar events are a shift where you have access to the user ID of the user for that shift..."
$shifts = ($calendar | Where-Object {($_.type = "shift") -and ($_.user)})


#loop through shifts and store the users for each
Write-Output "Checking for duplicate shifts..."
$allShiftUsers = $shifts.user.id
$uniqueShiftUsers = ($allShiftUsers | Select-Object -Unique)
$duplicateUsers = (Compare-Object -ReferenceObject $allShiftUsers -DifferenceObject $uniqueShiftUsers).InputObject

foreach ($duplicateUserID in $duplicateUsers) {
    $duplicateShifts = ($shifts | Where-Object {$PSItem.user.id -eq $duplicateUserID})
    $duplicateUser = ($users | Where-Object {$_.id -eq $duplicateUserID})
    $duplicateUserName = ($duplicateUser.name + " " + $duplicateUser.lastname)
    $duplicateUserPhone = $duplicateUser.phone
    $informationString = "`n$duplicateUserName"
    if ($duplicateUserPhone) {
        $informationString += " ($duplicateUserPhone)"
    }
    $informationString += " signed up for shifts at:`n"
    foreach ($duplicateShift in $duplicateShifts) {
        $duplicateLocation = ($groups.($duplicateShift.location.id).name)
        $informationString += "$duplicateLocation`n"
    }
    Write-Output $informationString
}