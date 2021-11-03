#A script to find and list off users who signed up for more than one shift tomorrow
#Interfaces with https://getsling.com/ scheduling platform

$base_url = "https://api.getsling.com/v1"

Write-Output "Checking authentication..."
#Check if we already have an authentication token (mostly for repetitive testing)
If ($Auth) {
    #If there is one, try to use it
    Try {
        #If we do succeed, save the information about the session.
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

#A couple handy variables for later
$userID = $SessionInfo.user.id
$orgID = $SessionInfo.org.id


#Prep the Authorization header
$Auth = ($Authorization.Replace("{","").Replace("}",""))
$headers = @{Authorization = $Auth; accept = "*/*"}

#Prep the Invoke-RequestMethod paramaters for most things
$irqParams = @{
    uri = ""
    headers = $headers
    method = "Get"
    #StatusCodeVariable = $statusCode
    #ResponseHeadersVariable = $ResponseHeaders
}

Write-Output "Getting a list of users and groups..."
#Get a list of user and group data

#Set the URI to use the endpoint for concise (read: complete) user and group information
$irqParams.uri = ($base_url + "/users/concise?user-fields=full")

#Get the data
$user_data = (Invoke-RestMethod @irqParams)

#Break it into useful chunks
$users = $user_data.users
$groups = $user_data.groups

Write-Output "Determining which groups are actually locations..."
#Get a list of groups that are employee positions
$locations = @()

#Okay, this part is dumb.
#The data about the groups are all their own object in the JSON where the object is a value in a name/value pair with a name that is the group id
#All of these name/value pairs are under the "groups" object
#This makes it harder to reference groups because instead of just doing $groups.location_id.informationwewant we have to do this
foreach ($group in ($groups | Get-Member | Where-Object {$_.MemberType -eq "NoteProperty"})) {
    If (($groups.($group.name).type) -eq "location") {
        $locations += $groups.($group.Name).id
    }
}

#Build Tomorrow in ISO8601 Time Duration
Write-Output "Building tomorrow..."
#Build tomorrow by adding one of each to today
$tomorrowYear = (Get-Date).AddDays(1).Year
$tomorrowMonth = (Get-Date).AddDays(1).Month
$tomorrowDay = (Get-Date).AddDays(1).Day
#Put it all together and spit it out in ISO8601 ("o")
$start = (Get-Date -Format "o" -Year $tomorrowYear -Month $tomorrowMonth -Day $tomorrowDay -Hour 0 -Minute 0 -Second 0 -Millisecond 0)
#Add the duration "PT24H", or "A duration of 24 hours"
$tomorrow = ("$start/PT24H")

#Get the users calendar (which is actually their "calendar view")
Write-Output "Getting your calendar for tomorrow..."
$irqParams.uri = ($base_url + "/$orgID/calendar/$orgID/users/$userID`?dates="  + ([uri]::EscapeDataString($tomorrow)))
$calendar = (Invoke-RestMethod @irqParams)
Write-Output "Determining which calendar events are a shift, of which you have access to the user ID of the user for that shift..."
#Sometimes the user property for the calendar event just doesn't exist. I don't know why. I assume it's a permissions thing.
$shifts = ($calendar | Where-Object {($_.type = "shift") -and ($_.user)})

#Check for duplicates
Write-Output "Checking for duplicate shifts tomorrow..."
#Add all the user IDs from the shifts to an array
$allShiftUsers = $shifts.user.id
#Make another array with just the user IDs that are unique
$uniqueShiftUsers = ($allShiftUsers | Select-Object -Unique)
#Get the user IDs of duplicates by figuring out which users are listed in "All" but not listed in "Unique"
$duplicateUsers = (Compare-Object -ReferenceObject $allShiftUsers -DifferenceObject $uniqueShiftUsers).InputObject

#Loop through listing off every user who signed up for duplicate shifts tomorrow
foreach ($duplicateUserID in $duplicateUsers) {
    #Get info about the shifts that have a duplicate user
    $duplicateShifts = ($shifts | Where-Object {$PSItem.user.id -eq $duplicateUserID})
    #Get info about the user who signed up for duplicate shift
    $duplicateUser = ($users | Where-Object {$_.id -eq $duplicateUserID})

    #I realize I could probably consolidate this next part into less lines. I'm not going to.
    #Putting together a complicated text string is hard enough without it all being on one line.
    
    #Build their full name
    $duplicateUserName = ($duplicateUser.name + " " + $duplicateUser.lastname)
    #Save their phone number
    $duplicateUserPhone = $duplicateUser.phone
    #Start off our string about the user and which shifts they signed up for with a new line (to make sure it's legible) and their name
    $informationString = "`n$duplicateUserName"
    #If they have their phone number on their profile, add that to the string in parenthesis
    if ($duplicateUserPhone) {
        $informationString += " ($duplicateUserPhone)"
    }
    #add this midway portion
    $informationString += " signed up for shifts at:`n"
    #add the name of the location of each shift on the new line.
    foreach ($duplicateShift in $duplicateShifts) {
        $duplicateLocation = ($groups.($duplicateShift.location.id).name)
        $informationString += "$duplicateLocation`n"
    }
    #Spit all this out
    Write-Output $informationString
}