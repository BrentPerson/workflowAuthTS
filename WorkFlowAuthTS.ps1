Add-PSSnapin microsoft.sharepoint.powershell -ErrorAction SilentlyContinue
$ErrorActionPreference = "Stop"
$Title = "Workflow Authentication Troubleshooter"
$Info = "What would you like to test? WFM security token trust? Check for issues with user profiles? Workflow App Only Policy Permissions?"
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&WFM Trust", "&User Profiles", "&App Permissions","&Quit")
[int]$defaultchoice = 3
$opt =  $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)

#This code calls to a Microsoft web endpoint to track how often it is used. 
#No data is sent on this call other than the application identifier
Add-Type -AssemblyName System.Net.Http
$client = New-Object -TypeName System.Net.Http.Httpclient
$cont = New-Object -TypeName System.Net.Http.StringContent("", [system.text.encoding]::UTF8, "application/json")
$tsk = $client.PostAsync("https://msapptracker.azurewebsites.net/api/Hits/0bf21b33-92cf-4338-a1d1-f17fa77bf1a1",$cont)

switch($opt)
{
    0 
    { 
        function getCert ([string] $certString)
        {
            [byte[]]$certBytes = [System.Text.Encoding]::ASCII.GetBytes($certString);
            $cxCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,$certBytes)
            return $cxCert
        }

        function checktrust
        {
            $wfmtrust = $null
            $success = $true
            $WFMmetadata = $null
            $WFMTrust = Get-SPTrustedSecurityTokenIssuer | ? DisplayName -eq "00000005-0000-0000-c000-000000000000"
            if($WFMTrust -eq $null)
            {
                Write-Host "there is no trusted security token issuer registered for WFM." -ForegroundColor Red
                break
            }

            $trustedcerts = Get-SPTrustedRootAuthority
            $trustedThumbPrints = $trustedcerts.Certificate.Thumbprint
            $WFMmetadata = Invoke-RestMethod -Method Get $WFMTrust.MetadataEndPoint -ErrorAction Stop
            $certs = @{} #New-Object System.Collections.Generic.List[System.Object]

            for($i=0;$i -lt $WFMmetadata.keys.Count; $i++){
                $cur = $(getCert -certString $WFMmetadata.keys[$i].keyValue.value)
                $certs.Add($cur.Thumbprint, $cur)
            }

            #check signing cert
            $signingCertValid = $certs.Contains($WFMTrust.SigningCertificate.Thumbprint)
            if($signingCertValid)
            { 
                Write-Host ""
                Write-Host "WFM Trust Certificate matches:  $($WFMTrust.SigningCertificate.Thumbprint) $($WFMTrust.SigningCertificate.Subject)" -ForegroundColor Green
            }
            else
            { 
                Write-Host ""
                Write-Host "The WFM Trust signing cert is incorrect!! Thumbprint: " $WFMTrust.SigningCertificate.Thumbprint
                $success = $false
                return $success
            }

            if($trustedThumbPrints.Contains($WFMTrust.SigningCertificate.Thumbprint))
            {
                Write-Host ""
                write-host "Certificate: " $WFMTrust.SigningCertificate.Thumbprint $WFMTrust.SigningCertificate.Subject "is trusted in the root authority" -ForegroundColor Yellow
                Write-Host ""
            }
            else
            {
                Write-Host ""
                Write-host "certificate is not trusted in the root authority adding it now" -ForegroundColor Red
                $new = New-SPTrustedRootAuthority -Name $WFMTrust.SigningCertificate.Issuer -Certificate $WFMTrust.SigningCertificate
                Write-Host ""
                $new
            }
            $numAdditionlCerts = $WFMTrust.AdditionalSigningCertificates.Count
            for($x=0;$x -lt $numAdditionlCerts;$x++)
            {
                $curCert = $WFMTrust.AdditionalSigningCertificates[$x]
                $curThumbprint = $curCert.Thumbprint
                if($certs.Contains($curThumbprint))
                {
                    Write-Host "Certificate matches: " $curThumbprint $curCert.Subject -ForegroundColor Green 
                }
                else
                {
                    Write-Host "Missing: " $curThumbprint $curCert.Subject -ForegroundColor Red
                    $success = $false 
                }
    
                if($trustedThumbPrints.Contains($curThumbprint))
                {
                    Write-Host "Additional Signing Certificate Thumbprint: $curThumbprint is trusted in the root authority. " -ForegroundColor Yellow
                }
                else
                {
                    Write-Host "Missing: "  $curThumbprint $curCert.Subject    "In the trusted root authority. Adding it now..." -ForegroundColor Red 
                    New-SPTrustedRootAuthority -Name "WFMTrustChain_$x" -Certificate $curCert
                }

            }
            return $success
        }


        Write-Host ""
        Write-Host "Checking WFM Trusted Security Token Issuer Token Signing Certificate" -ForegroundColor Green
        
        $trust = checktrust
        while($trust -eq $false)
        {
            $fix = Read-Host "Would you like to run the timer job 'RefreshMetadataFeed' in an attempt to correct this certificate issue? Yes or No?"
            if($fix -eq "Y" -or $fix -eq "y" -or $fix -eq "Yes" -or $fix -eq "yes")
            {
                $tj = Get-SPTimerJob | ? Name -eq "RefreshMetadataFeed"
                if($tj)
                {
                    write-host "Running Timer Job '$($tj.Name)'" -ForegroundColor Yellow
                    $tj.RunNow()
                    write-host "Will check again in 20 seconds....." -ForegroundColor Yellow
                    sleep -Seconds 20
                    Write-Host "Checking the WFM trust again..."
                    $trust = checktrust
                }
                else
                {
                    Write-Host "'Refresh Security Token Service Metadata Feed' does not exist see ULS logs for details.  You will have to manualy update the trust certificate." -ForegroundColor Red
                    break
                }  
            }
            else
            {
                Write-host "Good Bye!!!" -ForegroundColor Green
                break
            }

        }
    }
    
    1 
    { 
        Write-Host ""
        $userUPN = Read-Host "Please Enter The Users UPN You'd like to check."
        $profileCount = 0
        $duplicates = @()
        $profileManager = [Microsoft.Office.Server.UserProfiles.UserProfileManager]([Microsoft.Office.Server.ServerContext]::Default)
        $userProfiles = $profileManager.GetEnumerator()
        
        while($userProfiles.MoveNext())
        {
            if($userProfiles.Current["SPS-UserPrincipalName"] -eq $userUPN)
            {
                $ErrorActionPreference = "SilentlyContinue"
                $profileCount += 1
                $duplicates += $userProfiles.Current
                $objUser = New-Object System.Security.Principal.NTAccount($userUPN) 
                $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
                
            }
        }
        if($profileCount -eq 0)
        {
            Write-Host ""
            write-Host "We did not find any user profiles matching the UPN '$userUPN'" -ForegroundColor Yellow
            break
        }
        elseif($profileCount -eq 1)
        {
            Write-Host ""
            Write-host "We found a user profile matching UPN '$userUPN'" -ForegroundColor Green
        }
        elseif($profileCount -gt 1)
        {
            Write-Host ""
            Write-Host "We found '$profileCount' user profiles matching UPN '$userUPN'" -ForegroundColor Red
        }
        Write-Host ""
        $ListProfiles = Read-Host "Would you like to display these profile(s)? Yes or No?"
        if($ListProfiles -eq "Yes" -or $ListProfiles -eq "yes" -or $ListProfiles -eq "y" -or $ListProfiles -eq "Y")
        {
            $duplicates
        }
        $duplicates = $null
    }

    2 
    {
        Write-Host ""
        $webURL = Read-Host "Please Enter The URL For The Web/SubSite You'd Like To Check"
        Write-Host ""
        Write-Host "Checking Workflow App Only Policy Permissions for '$webURL'" -ForegroundColor Yellow
       
        $web = get-spweb $webURL -ErrorAction Stop
        $appPrincipals = $web.GetSiteAppPrincipals() | ? DisplayName -eq "Workflow"
        if(!$appPrincipals)
        {
            write-host "There are no App Principals registered on this web for Workflows. Check the registered apps for the site." -ForegroundColor Red
            break
        }
        else
        {
            $feature = Get-SPFeature -Identity "WorkflowAppOnlyPolicyManager" -Web $webURL -Limit All
        }

        if($feature)
        {
            Write-Host ""
            Write-Host "Web '$webURL' is allowing workflows to use App Only permissions under the following AppId's: " -ForegroundColor Green
            Write-Host ""
            Write-Host $appPrincipals.EncodedIdentityClaim
            Write-Host ""
        }
        else
        {
            Write-Host "Web '$webURL' is NOT allowing workflows to use App Only permissions."
            $activateFeature = Read-Host "Would you like to activate the workflow feature 'Workflows can use app permissions' on web '$webURL?' Enter Y or N"

            if($activateFeature -eq "Y" -or $activateFeature -eq "y")
            {
                Write-Host "Activate Feature standby......" -ForegroundColor Yellow
                Enable-SPFeature -Identity "WorkflowAppOnlyPolicyManager" -Url $webURL -ErrorAction Stop
            }
            else
            {
                Write-host "Good Bye!!!" -ForegroundColor Green
                break
            }
        }
    }

    3
    {
        Write-host "Good Bye!!!" -ForegroundColor Green
        break
    }
}