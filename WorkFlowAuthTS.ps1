Add-PSSnapin microsoft.sharepoint.powershell -ErrorAction SilentlyContinue
$ErrorActionPreference = "Stop"
$Title = "Workflow Authentication Troubleshooter"
$Info = "What would you like to test? WFM Trust Signing Certificate? Duplicate User Profiles? Workflow App Permissions?"
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&WFM Trust", "&User Profiles", "&App Permissions","&Quit")
[int]$defaultchoice = 3
$opt =  $host.UI.PromptForChoice($Title , $Info , $Options,$defaultchoice)
switch($opt)
{
    0 
    { 
        Write-Host ""
        Write-Host "Checking WFM Trusted Security Token Issuer Token Signing Certificate" -ForegroundColor Green
        function getCert ([string] $certString)
        {
            [byte[]]$certBytes = [System.Text.Encoding]::ASCII.GetBytes($certString);
            $cxCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,$certBytes)
            return $cxCert
        }

        $WFMTrust = Get-SPTrustedSecurityTokenIssuer | ? DisplayName -eq "00000005-0000-0000-c000-000000000000"
        if($WFMTrust -eq $null)
        {
            #throw error and stop
        }

        $trustedcerts = Get-SPTrustedRootAuthority
        $trustedThumbPrints = $trustedcerts.Certificate.Thumbprint
        $WFMmetadata = Invoke-RestMethod -Method Get $WFMTrust.MetadataEndPoint
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
                $profileCount += 1
                $duplicates += $userProfiles.Current
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
        Write-Host "Checking Workflow App Permissions for '$webURL'" -ForegroundColor Yellow
        try
        {
            $web = get-spweb $webURL
            $appPrincipals = $web.GetSiteAppPrincipals() | ? DisplayName -eq "Workflow"
        }
        catch
        {
             Write-Host $_.Exception.Message
             Write-host "Good Bye!!!" -ForegroundColor Green
             break
        }

        $feature = Get-SPFeature -Identity "WorkflowAppOnlyPolicyManager" -Web $webURL -Limit All

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

