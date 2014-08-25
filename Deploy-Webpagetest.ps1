#region Deployment of IIS, FTP and ASP .Net Site
Function Deploy-AspdotNet(){
    [CmdletBinding()]
    Param(
        [String]$DomainName = "example.com",
        [String]$FtpUserName = "ftpuser01",
        [String]$FtpPassword = "Passw0rd",
        [String]$Logfile = "C:\Windows\Temp\Deploy-AspdotNet.log"
    )
    Set-Content .\super.txt $FtpPassword
    #region Create Log File
        if (!( Test-Path $Logfile)){
            New-Item -Path "C:\Windows\Temp\Deploy-AspdotNet.log" -ItemType file
        }
        #endregion
    #region Write Log file
    Function WriteLog{
        Param ([string]$logstring)
        Add-content $Logfile -value $logstring
    }
    #endregion
    #region Variables
    $webRoot = "$env:systemdrive\inetpub\wwwroot\"
    $webFolder = $webRoot + $DomainName
    $appPoolName = $DomainName
    $siteName = $DomainName
    $ftpName = "ftp_" + $DomainName
    $appPoolIdentity = "IIS AppPool\$appPoolName"
    #endregion
    #region Create Automation Login
    Function Create-User($User,$Password) {
      try{
          if($Password -match $null){
              Write-Host "[$(Get-Date)] Error: wffadmin is set with the password $Password"
          }
          $hostname = $env:ComputerName
          $objComputer = [ADSI]("WinNT://$hostname,computer")
          $colUsers = ($objComputer.psbase.children |
              Where-Object {$_.psBase.schemaClassName -eq "User"} |
                  Select-Object -expand Name)
          if($colUsers -contains $User){
              ([ADSI]("WinNT://$hostname/$User")).SetPassword($Password)
              WMIC USERACCOUNT WHERE "Name='$User'" SET PasswordExpires=FALSE >$null
              Write-Host "[$(Get-Date)] Status: Completed $user update with password $Password"
          }
          else {
              net user /add $User $Password /expires:never /passwordchg:no /comment:"Automation" > $null
              WMIC USERACCOUNT WHERE "Name='$User'" SET PasswordExpires=FALSE > $null
              net localgroup administrators $User /add > $null
              Write-Host "[$(Get-Date)] Status: Completed $user creation with password $Password"
              #return $Password
          }
      }
      catch [Exception] {
          Write-Host "[$(Get-Date)] Error: $_"
          return
      }
  }
    #endregion
    #region Install IIS and ASP
    Function Install-AspWebServer (){
    Write-Host "[$(Get-Date)] Installing IIS and ASP .Net"
    Import-Module servermanager
    Add-WindowsFeature Web-Server,Web-WebServer,Web-Common-Http,Web-Default-Doc,Web-Dir-Browsing,Web-Http-Errors,Web-Static-Content,Web-Http-Redirect,Web-Health,Web-Http-Logging,Web-Custom-Logging,Web-Log-Libraries,Web-ODBC-Logging,Web-Request-Monitor,Web-Http-Tracing,Web-Performance,Web-Stat-Compression,Web-Dyn-Compression,Web-Security,Web-Filtering,Web-Basic-Auth,Web-CertProvider,Web-Client-Auth,Web-Digest-Auth,Web-Cert-Auth,Web-IP-Security,Web-Url-Auth,Web-Windows-Auth,Web-App-Dev,Web-Net-Ext,Web-Net-Ext45,Web-AppInit,Web-ASP,Web-Asp-Net,Web-Asp-Net45,Web-CGI,Web-ISAPI-Ext,Web-ISAPI-Filter,Web-Includes,Web-WebSockets,Web-Mgmt-Tools,Web-Mgmt-Console,Web-Mgmt-Compat,Web-Metabase,Web-Lgcy-Mgmt-Console,Web-Scripting-Tools > $null
  }
    #endregion
    #region Install FTP
    Function Install-FTPserver () {
        Import-Module ServerManager
        $out = Add-WindowsFeature -Name Web-Ftp-Server -IncludeAllSubFeature
        if ($out.ExitCode -eq "NoChangeNeeded"){
            Write-Host "[$(Get-Date)] FTP server is already installed"
        }
        else {
            Write-Host "[$(Get-Date)] FTP Server and dependencies have been installed"
        }
    }
    #endregion
    #region Create A Website in IIS
    Function Create-Website ($webSiteName, $webSiteFolder, $webAppPoolName){
    try{
      Write-Host "[$(Get-Date)] Creating the $webSiteName"
      New-Item $webSiteFolder -type directory -Force >$null
      Stop-Website -Name 'Default Web Site'
      New-WebAppPool $webAppPoolName > $null
      New-Website -Name $webSiteName -Port 80 -IPAddress "*" -HostHeader $webSiteName -PhysicalPath $webSiteFolder -ApplicationPool $webAppPoolName -Force > $null
    }
    catch{
      throw "Error : $_"
    }
  }
    #endregion
    #region Remove a Website in IIS
    Function Remove-Website($webAppPoolName, $webSiteFolder, $webSiteName){
    try{
    if($webSiteFolder -ne $null){
      if((Test-Path -PathType Container -path $webSiteFolder)){
        $siteStatus = get-website -Name $webSiteName
        $siteAppPoolStatus = Get-Item "IIS:\AppPools\$webSiteName"
        if((Get-WebsiteState -Name "$webSiteName").Value -ne "Stopped") {
          $siteStatus.Stop()
        }
        if((Get-WebAppPoolState -Name $webAppPoolName).Value -ne "Stopped") {
          $siteAppPoolStatus.Stop()
        }
        Write-Host "[$(Get-Date)] Removing the Web site $webSiteName"
        Remove-Website -Name $webSiteName
        Write-Host "[$(Get-Date)] Removing the Application pool $webAppPoolName"
        Remove-WebAppPool -Name $webAppPoolName
        Write-Host "[$(Get-Date)] Removing the Site Directory if $webAppPoolName"
        Remove-Item $webSiteFolder -Recurse -Force
      }
      else{
        Write-Host "[$(Get-Date)] The site $webSiteName is not present"
      }
    }
    }
    catch{
        throw "Error : $_"
    }
  }
    #endregion
    #region Create a FTP site
    Function Create-FtpSite($DefaultFtpSiteName,$DefaultFtpUser,$DefaultFtpPassword){
    function New-SelfSignedCert{
        [CmdletBinding()]
        [OutputType([int])]
        Param
        (
            [Parameter(Mandatory=$true,
                       ValueFromPipeLine=$true,
                       Position=0)]
            [string[]]$Subject = "demo.demo.com"
            ,
            [Parameter(Mandatory=$true,
                       ValueFromPipelineByPropertyName=$true,
                       Position=1)]
            [ValidateSet("User","Computer")]
            [string]$CertStore = "Computer"
            ,
            [ValidateSet("Y","N")]
            [string]$EKU_ServerAuth =  "Y"
            ,
            [ValidateSet("Y","N")]
            [string]$EKU_ClientAuth =  "Y"
            ,
            [ValidateSet("Y","N")]
            [string]$EKU_SmartCardAuth =  "Y"
            ,
            [ValidateSet("Y","N")]
            [string]$EKU_EncryptFileSystem =  "Y"
            ,
            [ValidateSet("Y","N")]
            [string]$EKU_CodeSigning =  "Y"
            ,
            [ValidateSet("Y","N")]
            [string]$AsTrustedRootCert =  "N"
        )
        Begin{
            $ErrorActionPreference = "SilentlyContinue"
            If ($CertStore -eq "User"){
                $machineContext = 0
                $initContext = 1
            }
            ElseIF ($CertStore -eq "Computer"){
                $machineContext = 1
                $initContext = 2
            }
            Else{
                Write-Error "Invalid selection"
                Exit
            }
        }
        Process{
            $OS = (Get-WmiObject Win32_OperatingSystem).Version
            if ($OS[0] -ge 6) {
                foreach ($sub in $Subject){
                    #Generate cert in local computer My store
                    $name = new-object -com "X509Enrollment.CX500DistinguishedName.1"
                    $name.Encode("CN=$sub", 0)
                    $key = new-object -com "X509Enrollment.CX509PrivateKey.1"
                    $key.ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
                    $key.KeySpec = 1
                    $key.Length = 2048
                    $key.SecurityDescriptor = "D:PAI(A;;0xd01f01ff;;;SY)(A;;0xd01f01ff;;;BA)(A;;0x80120089;;;NS)"
                    $key.MachineContext = $machineContext
                    $key.ExportPolicy = 1
                    $key.Create()
                    $ekuoids = new-object -com "X509Enrollment.CObjectIds.1"
                    #Enhanced Key Usage `(EKU`) by answering Y/N
                    If ($EKU_ServerAuth -eq "Y"){
                    $serverauthoid = new-object -com "X509Enrollment.CObjectId.1"
                    $serverauthoid.InitializeFromValue("1.3.6.1.5.5.7.3.1")
                    $ekuoids.add($serverauthoid)
                    }
                    If ($EKU_ClientAuth -eq "Y"){
                    $clientauthoid = new-object -com "X509Enrollment.CObjectId.1"
                    $clientauthoid.InitializeFromValue("1.3.6.1.5.5.7.3.2")
                    $ekuoids.add($clientauthoid)
                    }
                    If ($EKU_SmartCardAuth -eq "Y"){
                    $smartcardoid = new-object -com "X509Enrollment.CObjectId.1"
                    $smartcardoid.InitializeFromValue("1.3.6.1.4.1.311.20.2.2")
                    $ekuoids.add($smartcardoid)
                    }
                    If ($EKU_EncryptFileSystem -eq "Y"){
                    $efsoid = new-object -com "X509Enrollment.CObjectId.1"
                    $efsoid.InitializeFromValue("1.3.6.1.4.1.311.10.3.4")
                    $ekuoids.add($efsoid)
                    }
                    If ($EKU_CodeSigning -eq "Y"){
                    $codesigningoid = new-object -com "X509Enrollment.CObjectId.1"
                    $codesigningoid.InitializeFromValue("1.3.6.1.5.5.7.3.3")
                    $ekuoids.add($codesigningoid)
                    }
                    $ekuext = new-object -com "X509Enrollment.CX509ExtensionEnhancedKeyUsage.1"
                    $ekuext.InitializeEncode($ekuoids)
                    $cert = new-object -com "X509Enrollment.CX509CertificateRequestCertificate.1"
                    $cert.InitializeFromPrivateKey($initContext, $key, "")
                    $cert.Subject = $name
                    $cert.Issuer = $cert.Subject
                    $cert.NotBefore = get-date
                    $cert.NotAfter = $cert.NotBefore.AddDays(3650)
                    $cert.X509Extensions.Add($ekuext)
                    $cert.Encode()
                    $enrollment = new-object -com "X509Enrollment.CX509Enrollment.1"
                    $enrollment.InitializeFromRequest($cert)
                    $certdata = $enrollment.CreateRequest(1)
                    $enrollment.InstallResponse(2, $certdata, 1, "")
                    Write-Verbose "$($sub) has been added the Certificate to the Store $($CertStore)"
                    #Install the certificate to Trusted Root Certification Authorities
                    if ($AsTrustedRootCert -eq "Y") {
                        [Byte[]]$bytes = [System.Convert]::FromBase64String($certdata)
                        foreach ($Store in "Root", "TrustedPublisher") {
                            $x509store = New-Object Security.Cryptography.X509Certificates.X509Store $Store, "LocalMachine"
                            $x509store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                            $x509store.Add([Security.Cryptography.X509Certificates.X509Certificate2]$bytes)
                            $x509store.Close()
                        }
                    }
                    Write-Verbose "$($sub) has been added the Certificate to the Store $($Store)"
                }
            }
            else{
                Write-Warning "The Operating System must be at LEAST Windows Server 2008"
            }
        }
        End{
        Write-Host "Completed :: New Certificate(s) Created and Installed" -ForegroundColor Green
        Write-Verbose "Execution finished..."
        }
    }
    Import-Module WebAdministration
    $DefaultFtpPath = "c:\inetpub\wwwroot\"
    $DefaultNonSecureFtpPort = 21
    # Create FTP user Account
    net user /add $DefaultFtpUser $DefaultFtpPassword > $null
    Write-Host "[$(Get-Date)] Completed '$DefaultFtpUser' creation"
    New-WebFtpSite -Name $DefaultFtpSiteName -PhysicalPath $DefaultFtpPath -Port $DefaultNonSecureFtpPort -IPAddress * > $null
    # Apply permissions to wwwroot Folder
    $acl = (Get-Item $DefaultFtpPath).GetAccessControl("Access")
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($DefaultFtpUser,"Modify","ContainerInherit, ObjectInherit","None","Allow")
    $acl.AddAccessRule($rule)
    Set-Acl $DefaultFtpPath $acl
    # Configure IIS Site Properties
    Set-ItemProperty IIS:\Sites\$DefaultFtpSiteName -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty IIS:\Sites\$DefaultFtpSiteName -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
    Set-ItemProperty IIS:\Sites\$DefaultFtpSiteName -Name ftpServer.security.ssl.ssl128 -Value $true
    Set-ItemProperty IIS:\Sites\$DefaultFtpSiteName -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    # Alter FTPServer Configuration
    # Add Allow rule for our ftpGroup (Permission=3 ==> Read+Write)
    Add-WebConfiguration "/system.ftpServer/security/authorization" -value @{accessType="Allow"; users=$DefaultFtpUser; permissions=3} -PSPath IIS:\ -location $DefaultFtpSiteName
    # Change the lower and upper dataChannel ports
    $firewallSupport = Get-WebConfiguration system.ftpServer/firewallSupport
    $firewallSupport.lowDataChannelPort = 5001
    $firewallSupport.highDataChannelPort = 5050
    $firewallSupport | Set-WebConfiguration system.ftpServer/firewallSupport
    New-SelfSignedCert -Subject $DefaultFtpSiteName -CertStore Computer -EKU_ServerAuth Y -EKU_ClientAuth Y -EKU_SmartCardAuth Y -EKU_EncryptFileSystem Y -EKU_CodeSigning Y -AsTrustedRootCert Y > $null
    cd Microsoft.PowerShell.Security\Certificate::localmachine\my
    $cert = Get-ChildItem | Where-Object {$_.subject -match $DefaultFtpSiteName } | select thumbprint | foreach { $_.thumbprint }
    Set-ItemProperty IIS:\Sites\$DefaultFtpSiteName -Name ftpServer.security.ssl.serverCertHash -Value $cert
    Write-Host "[$(Get-Date)] FTP Certificate $cert"
    Write-Host "[$(Get-Date)] Completed $DefaultFtpSiteName creation"
    netsh advfirewall set global StatefulFTP disable > $null
    Write-Host "[$(Get-Date)] Stateful FTP is disabled"
    Write-Host "[$(Get-Date)] Restart FTP service"
    Restart-Service ftpsvc > $null
    cd c:\
}
    #endregion
    #region Enable HTTP and HTTPS ports
    Function Enable-WebServerFirewall(){
    write-host "[$(Get-Date)] Enabling port 80"
    netsh advfirewall firewall set rule group="World Wide Web Services (HTTP)" new enable=yes > $null
    write-host "[$(Get-Date)] Enabling port 443"
    netsh advfirewall firewall set rule group="Secure World Wide Web Services (HTTPS)" new enable=yes > $null
  }
    #endregion
    #region Clean Deployment
    Function Clean-Deployment{
        #region Remove Automation initial firewall rule opener
        if((Test-Path -Path 'C:\Cloud-Automation')){
            Remove-Item -Path 'C:\Cloud-Automation' -Recurse > $null
        }
        #endregion
        #region Schedule Task to remove the Psexec firewall rule
        $DeletePsexec = {
            Remove-Item $MyINvocation.InvocationName
            $find_rule = netsh advfirewall firewall show rule "PSexec Port"
            if ($find_rule -notcontains 'No rules match the specified criteria.') {
                Write-Host "Deleting firewall rule"
                netsh advfirewall firewall delete rule name="PSexec Port" > $null
            }
        }
        $Cleaner = "C:\Windows\Temp\cleanup.ps1"
        Set-Content $Cleaner $DeletePsexec
        $ST_Username = "autoadmin"
        net user /add $ST_Username $FtpPassword
        net localgroup administrators $ST_Username /add
        $ST_Exec = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        $ST_Arg = "-NoLogo -NonInteractive -WindowStyle Hidden -ExecutionPolicy ByPass C:\Windows\Temp\cleanup.ps1"
        $ST_A_Deploy_Cleaner = New-ScheduledTaskAction -Execute $ST_Exec -Argument $ST_Arg
        $ST_T_Deploy_Cleaner = New-ScheduledTaskTrigger -Once -At ((Get-date).AddMinutes(2))
        $ST_S_Deploy_Cleaner = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances Parallel
        #$ST_ST_Deploy_Cleaner = New-ScheduledTask -Action $ST_A_Deploy_Cleaner -Trigger $ST_T_Deploy_Cleaner -Settings $ST_S_Deploy_Cleaner
        Register-ScheduledTask -TaskName "Clean Automation" -TaskPath \ -RunLevel Highest -Action $ST_A_Deploy_Cleaner -Trigger $ST_T_Deploy_Cleaner -Settings $ST_S_Deploy_Cleaner -User $ST_Username -Password $FtpPassword *>> $Logfile
        #endregion
    }
    #endregion
    #region MAIN
    Install-AspWebServer
    Install-FTPserver
    Create-Website -webSiteName $siteName -webSiteFolder $webFolder -webAppPoolName $appPoolName
    Set-Content .\super.txt "$FtpPassword"
    Create-FtpSite -DefaultFtpSiteName $ftpName -DefaultFtpUser $FtpUserName -DefaultFtpPassword $FtpPassword
    Enable-WebServerFirewall
    Clean-Deployment
    #endregion
#################################################################
$wpt_zip_url =  "https://github.com/WPO-Foundation/webpagetest/releases/download/WebPagetest-2.15/webpagetest_2.15.zip"
$driver_installer_url = "http://9cecab0681d23f5b71fb-642758a7a3ed7927f3ce8478e9844e11.r45.cf5.rackcdn.com/mindinst.exe"
$driver_installer_cert_url = "https://github.com/Linuturk/webpagetest/raw/master/webpagetest/powershell/WPOFoundation.cer"
$wpt_host =  $env:COMPUTERNAME
$wpt_user = "webpagetest"
$wpt_password = $FtpPassword
$wpt_zip_file = "webpagetest_2.15.zip"
$driver_installer_file = "mindinst.exe"
$driver_installer_cert_file = "WPOFoundation.cer"
    $wpt_agent_dir = "c:\wpt-agent"
    $wpt_www_dir = "c:\wpt-www"
    $wpt_temp_dir = "C:\wpt-temp"
function Set-WptFolders(){
    $wpt_folders = @($wpt_agent_dir,$wpt_www_dir,$wpt_temp_dir)
    foreach ($wpt_folder in $wpt_folders){
        New-Item $wpt_folder -type directory -Force > $null
    }
}
function Download-File ($url, $localpath, $filename){
    if(!(Test-Path -Path $localpath)){
        New-Item $localpath -type directory > $null
    }
    $webclient = New-Object System.Net.WebClient;
    $webclient.DownloadFile($url, $localpath + "\" + $filename)
}
function Unzip-File($fileName, $sourcePath, $destinationPath){
    $shell = new-object -com shell.application
    if (!(Test-Path "$sourcePath\$fileName")){
        throw "$sourcePath\$fileName does not exist"
    }
    New-Item -ItemType Directory -Force -Path $destinationPath -WarningAction SilentlyContinue
    $shell.namespace($destinationPath).copyhere($shell.namespace("$sourcePath\$fileName").items())
}
function Set-WebPageTestUser ($Username, $Password){
    $Exists = [ADSI]::Exists("WinNT://./$Username")
    if ($Exists) {
        Write-Output "[$(Get-Date)] $Username user already exists."
    } Else {
        net user /add $Username
        net localgroup Administrators /add $Username
        $user = [ADSI]("WinNT://./$Username")
        $user.SetPassword($Password)
        $user.SetInfo()
        Write-Output "[$(Get-Date)] $Username created."
    }
}
function Set-AutoLogon ($Username, $Password){
    $LogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $CurrentVal = Get-ItemProperty -Path $LogonPath -Name AutoAdminLogon
    If ($CurrentVal.AutoAdminLogon -eq 1) {
        $CurrentUser = Get-ItemProperty -Path $LogonPath -Name DefaultUserName
        $CurrentPass = Get-ItemProperty -Path $LogonPath -Name DefaultPassword
        If ($CurrentUser.DefaultUserName -ne $Username -Or $CurrentPass.DefaultPassword -ne $Password) {
            Set-ItemProperty -Path $LogonPath -Name DefaultUserName -Value $Username
            Set-ItemProperty -Path $LogonPath -Name DefaultPassword -Value $Password
            Write-Output "[$(Get-Date)] Credentials Updated."
        }Else {
            Write-Output "[$(Get-Date)] AutoLogon already enabled."
        }
    }Else {
        Set-ItemProperty -Path $LogonPath -Name AutoAdminLogon -Value 1
        New-ItemProperty -Path $LogonPath -Name DefaultUserName -Value $Username
        New-ItemProperty -Path $LogonPath -Name DefaultPassword -Value $Password
        Write-Output "[$(Get-Date)] AutoLogon enabled."
    }
}
function Set-DisableServerManager (){
    $CurrentState = Get-ScheduledTask -TaskName "ServerManager"
    If ($CurrentState.State -eq "Ready") {
        Get-ScheduledTask -TaskName "ServerManager" | Disable-ScheduledTask
        Write-Output "[$(Get-Date)] Server Manager disabled at logon."
    } Else {
        Write-Output "[$(Get-Date)] Server Manager already disabled at logon."
    }
}
function Set-MonitorTimeout (){
    $CurrentVal = POWERCFG /QUERY SCHEME_BALANCED SUB_VIDEO VIDEOIDLE | Select-String -pattern "Current AC Power Setting Index:"
    If ($CurrentVal -like "*0x00000000*") {
        Write-Output "[$(Get-Date)] Display Timeout already set to Never."
    } Else {
        POWERCFG /CHANGE -monitor-timeout-ac 0
        Write-Output "[$(Get-Date)] Display Timeout set to Never."
    }
}
function Set-DisableScreensaver (){
    $Path = 'HKCU:\Control Panel\Desktop'
    Try {
      $CurrentVal = Get-ItemProperty -Path $Path -Name ScreenSaveActive
      Write-Output "[$(Get-Date)] $CurrentVal"
    } Catch {
      $CurrentVal = False
    } Finally {
      if ($CurrentVal.ScreenSaveActive -ne 0) {
        Set-ItemProperty -Path $Path -Name ScreenSaveActive -Value 0
        Write-Output "[$(Get-Date)] Screensaver Disabled."
      } Else {
        Write-Output "[$(Get-Date)] Screensaver Already Disabled."
      }
    }
}
function Set-DisableUAC (){
    $Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $CurrentVal = Get-ItemProperty -Path $Path -Name ConsentPromptBehaviorAdmin
    if ($CurrentVal.ConsentPromptBehaviorAdmin -ne 00000000) {
        Set-ItemProperty -Path $Path -Name "ConsentPromptBehaviorAdmin" -Value 00000000
        Write-Output "[$(Get-Date)] UAC Disabled."
    } Else {
        Write-Output "[$(Get-Date)] UAC Already Disabled."
    }
}
function Set-DisableIESecurity (){
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    $CurrentVal = Get-ItemProperty -Path $AdminKey -Name "IsInstalled"
    if ($CurrentVal.IsInstalled -ne 0) {
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
        Write-Output "[$(Get-Date)] IE ESC Disabled."
    } Else {
        Write-Output "[$(Get-Date)] IE ESC Already Disabled."
    }
}
function Set-StableClock (){
    $useplatformclock = bcdedit | Select-String -pattern "useplatformclock        Yes"
    if ($useplatformclock) {
        Write-Output "[$(Get-Date)] Platform Clock Already Enabled."
    } Else {
        bcdedit /set  useplatformclock true
        Write-Output "[$(Get-Date)] Platform Clock Enabled."
    }
}
function Set-DisableShutdownTracker (){
    $Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Reliability'
    Try {
        $CurrentVal = Get-ItemProperty -Path $Path -Name ShutdownReasonUI
        Write-Output "[$(Get-Date)] $CurrentVal"
    } Catch {
        $CurrentVal = False
    } Finally {
        if ($CurrentVal.ShutdownReasonUI -ne 0) {
            New-ItemProperty -Path $Path -Name ShutdownReasonUI -Value 0
            Write-Output "[$(Get-Date)] Shutdown Tracker Disabled."
        }Else{
            Write-Output "[$(Get-Date)] Shutdown Tracker Already Disabled."
        }
    }
}
Function Set-WebPageTestInstall ($tempDir,$AgentDir,$wwwDir){
    Copy-Item -Path $AgentDir\agent\* -Destination C:\wpt-agent -Recurse -Force
    Copy-Item -Path $AgentDir\www\* -Destination C:\wpt-www -Recurse -Force
}
function Set-InstallAviSynth ($InstallDir){
    $Installed = Test-Path "C:\Program Files (x86)\AviSynth 2.5" -pathType container
    If ($Installed) {
        Write-Output "[$(Get-Date)] AviSynth already installed."
    } Else {
        & "$InstallDir\Avisynth_258.exe" /S
        Write-Output "[$(Get-Date)] AviSynth installed."
    }
}
function Set-InstallDummyNet ($InstallDir){
    Download-File -url $driver_installer_url -localpath $InstallDir -filename $driver_installer_file
    Download-File -url $driver_installer_cert_url -localpath $InstallDir -filename $driver_installer_cert_file
    $testsigning = bcdedit | Select-String -pattern "testsigning Yes"
    if ($testsigning) {
        Write-Output "[$(Get-Date)] Test Signing Already Enabled."
    } Else {
        bcdedit /set TESTSIGNING ON
        Write-Output "[$(Get-Date)] Test Signing Enabled."
    }
    $dummynet = Get-NetAdapterBinding -Name public*
    if ($dummynet.ComponentID -eq "ipfw+dummynet"){
        If ($dummynet.Enabled ) {
            Write-Output "[$(Get-Date)] ipfw+dummynet binding on the public network adapter is already enabled."
        } Else {
            Enable-NetAdapterBinding -Name public0 -DisplayName ipfw+dummynet
            Disable-NetAdapterBinding -Name private0 -DisplayName ipfw+dummynet
        }
    }
    else{
        Write-Output "[$(Get-Date)]  $InstallDir\$driver_installer_cert_file"
        Import-Certificate -FilePath C:\wpt-agent\WPOFoundation.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
        cd $InstallDir
        .\mindinst.exe C:\wpt-agent\dummynet\64bit\netipfw.inf -i -s
        Enable-NetAdapterBinding -Name private0 -DisplayName ipfw+dummynet
        Write-Output "[$(Get-Date)] Enabled ipfw+dummynet binding on the private network adapter."
    }
}
function Set-WebPageTestScheduledTask ($ThisHost, $User,$InstallDir){
    $GetTask = Get-ScheduledTask
    if ($GetTask.TaskName -match "wptdriver") {
        Write-Output "[$(Get-Date)] Task (wptdriver) already scheduled."
    } Else {
        $A = New-ScheduledTaskAction -Execute "$InstallDir\wptdriver.exe"
        $T = New-ScheduledTaskTrigger -AtLogon -User $User
        $S = New-ScheduledTaskSettingsSet
        $P = New-ScheduledTaskPrincipal -UserId "$ThisHost\$User" -LogonType ServiceAccount
        Register-ScheduledTask -TaskName "wptdriver" -Action $A -Trigger $T -Setting $S -Principal $P
        Write-Output "[$(Get-Date)] Task (wptdriver) scheduled."
    }
    $GetTask = Get-ScheduledTask
    if ($GetTask.TaskName -match "urlBlast") {
        Write-Output "[$(Get-Date)] Task (urlBlast) already scheduled."
    } Else {
        $A = New-ScheduledTaskAction -Execute "$InstallDir\urlBlast.exe"
        $T = New-ScheduledTaskTrigger -AtLogon -User $User
        $S = New-ScheduledTaskSettingsSet
        $P = New-ScheduledTaskPrincipal -UserId "$ThisHost\$User" -LogonType ServiceAccount
        Register-ScheduledTask -TaskName "urlBlast" -Action $A -Trigger $T -Setting $S -Principal $P
        Write-Output "[$(Get-Date)] Task (urlBlast) scheduled."
    }
}
function Set-ClosePort445 (){
    $CurrentVal = Get-NetFirewallRule -Name "PSexec Port"
    if ($CurrentVal.Enabled -eq "True") {
        Disable-NetFirewallRule -Name "PSexec Port"
        Write-Output "[$(Get-Date)] Port PSexec Port Disabled."
    } Else {
        Write-Output "[$(Get-Date)] Port PSexec Port Already Disabled."
    }
}
#region => Main
Set-WptFolders
Download-File -url $wpt_zip_url -localpath $wpt_temp_dir -filename $wpt_zip_file
Download-File -url $driver_installer_url -localpath $wpt_agent_dir -filename $driver_installer_file
Download-File -url $driver_installer_cert_url -localpath $wpt_temp_dir -filename $driver_installer_cert_file
Unzip-File -fileName $wpt_zip_file -sourcePath $wpt_temp_dir -destinationPath $wpt_agent_dir
Set-WebPageTestUser -Username $wpt_user -Password $wpt_password
Set-AutoLogon -Username $wpt_user -Password $wpt_password
Set-DisableServerManager
Set-MonitorTimeout
Set-DisableScreensaver
Set-DisableUAC
Set-DisableIESecurity
Set-StableClock
Set-DisableShutdownTracker
Set-WebPageTestInstall -tempDir $wpt_temp_dir -AgentDir $wpt_agent_dir
Set-InstallAviSynth -InstallDir $wpt_agent_dir
Set-InstallDummyNet -InstallDir $wpt_agent_dir
Set-WebPageTestScheduledTask -ThisHost $wpt_host -User $wpt_user -InstallDir $wpt_agent_dir
Set-ClosePort445
#endregion
#################################################################
}
#endregion
#region MAIN : Deploy ASP .Net site with FTP
#region Delete myself from the filesystem during execution
#Remove-Item $MyINvocation.InvocationName
#endregion
New-Item -ItemType file -Name super.txt
Deploy-AspdotNet -DomainName "%%sitedomain" -FtpUserName "%%ftpusername" -FtpPassword "%%ftppassword"
#endregion