function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Url,
        [parameter(Mandatory = $true)]  [ValidateSet("WebApplication","SiteCollection")] [System.String] $SettingsScope,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSharePointDesigner,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowDetachPagesFromDefinition,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCustomiseMasterPage,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowManageSiteURLStructure,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCreateDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSavePublishDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSaveDeclarativeWorkflowAsTemplate,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Getting SharePoint Designer configuration settings"

    switch ($SettingsScope) {
        "WebApplication" {
            $result = Invoke-SPDSCCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
                $params = $args[0]
        
                try {
                    $spFarm = Get-SPFarm
                } catch {
                    Write-Verbose -Verbose "No local SharePoint farm was detected. SharePoint Designer settings will not be applied"
                    return $null
                }

                # Check if web application exists
                $webapp = Get-SPWebApplication | Where-Object -FilterScript { ($_.Url).StartsWith($params.Url) }
                if ($null -eq $webapp) {
                    Write-Verbose -Verbose "Web application not found. SharePoint Designer settings will not be applied"
                    return $null
                } else {
                    # Get SPD settings for the web application
                    $spdSettings = Get-SPDesignerSettings $params.Url
        
                    return @{
                        # Set the SPD settings
                        Url = $params.Url
                        SettingsScope = $params.SettingsScope
                        AllowSharePointDesigner = $spdSettings.AllowDesigner
                        AllowDetachPagesFromDefinition = $spdSettings.AllowRevertFromTemplate
                        AllowCustomiseMasterPage = $spdSettings.AllowMasterPageEditing
                        AllowManageSiteURLStructure = $spdSettings.ShowURLStructure
                        AllowCreateDeclarativeWorkflow = $spdSettings.AllowCreateDeclarativeWorkflow
                        AllowSavePublishDeclarativeWorkflow = $spdSettings.AllowSavePublishDeclarativeWorkflow
                        AllowSaveDeclarativeWorkflowAsTemplate = $spdSettings.AllowSaveDeclarativeWorkflowAsTemplate
                        InstallAccount = $params.InstallAccount
                    }
                }
            }
        }
        "SiteCollection" {
            if ((Test-SPDSCRunAsCredential -Credential $InstallAccount) -eq $true) {
                $result = Invoke-SPDSCCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
                    $params = $args[0]
        
                    try {
                        $spFarm = Get-SPFarm
                    } catch {
                        Write-Verbose -Verbose "No local SharePoint farm was detected. SharePoint Designer settings will not be applied"
                        return $null
                    }

                    # Check if site collections exists
                    $site = Get-SPSite | Where-Object -FilterScript { $_.Url -eq $url }
                    if ($null -eq $site) {
                        Write-Verbose -Verbose "Site collection not found. SharePoint Designer settings will not be applied"
                        return $null
                    } else {
                        return @{
                            # Set the SPD settings
                            Url = $params.Url
                            SettingsScope = $params.SettingsScope
                            AllowSharePointDesigner = $site.AllowDesigner
                            AllowDetachPagesFromDefinition = $site.AllowRevertFromTemplate
                            AllowCustomiseMasterPage = $site.AllowMasterPageEditing
                            AllowManageSiteURLStructure = $site.ShowURLStructure
                            AllowCreateDeclarativeWorkflow = $site.AllowCreateDeclarativeWorkflow
                            AllowSavePublishDeclarativeWorkflow = $site.AllowSavePublishDeclarativeWorkflow
                            AllowSaveDeclarativeWorkflowAsTemplate = $site.AllowSaveDeclarativeWorkflowAsTemplate
                            InstallAccount = $params.InstallAccount
                        }
                    }
                }
            } else {
                throw "A known issue exists that prevents these settings from being managed when InstallAccount is used instead of PsDscRunAsAccount. See http://aka.ms/xSharePointRemoteIssues for details."
            }
        }
    }

    return $result
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Url,
        [parameter(Mandatory = $true)]  [ValidateSet("WebApplication","SiteCollection")] [System.String] $SettingsScope,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSharePointDesigner,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowDetachPagesFromDefinition,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCustomiseMasterPage,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowManageSiteURLStructure,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCreateDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSavePublishDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSaveDeclarativeWorkflowAsTemplate,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Setting SharePoint Designer configuration settings"

    switch ($SettingsScope) {
        "WebApplication" {
            Invoke-SPDSCCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
                $params = $args[0]

                try {
                    $spFarm = Get-SPFarm
                } catch {
                    throw "No local SharePoint farm was detected. SharePoint Designer settings will not be applied"
                    return
                }
        
                Write-Verbose -Verbose "Start update SPD web application settings"

                # Check if web application exists
                $webapp = Get-SPWebApplication | Where-Object -FilterScript { ($_.Url).StartsWith($params.Url) }
                if ($null -eq $webapp) {
                    throw "Web application not found. SharePoint Designer settings will not be applied"
                    return
                } else {
                    # Set the SharePoint Designer settings
                    if ($params.ContainsKey("AllowSharePointDesigner")) { $webapp.AllowDesigner = $params.AllowSharePointDesigner }
                    if ($params.ContainsKey("AllowDetachPagesFromDefinition")) { $webapp.AllowRevertFromTemplate = $params.AllowDetachPagesFromDefinition }
                    if ($params.ContainsKey("AllowCustomiseMasterPage")) { $webapp.AllowMasterPageEditing = $params.AllowCustomiseMasterPage }
                    if ($params.ContainsKey("AllowManageSiteURLStructure")) {$webapp.ShowURLStructure = $params.AllowManageSiteURLStructure }
                    if ($params.ContainsKey("AllowCreateDeclarativeWorkflow")) { $webapp.AllowCreateDeclarativeWorkflow = $params.AllowCreateDeclarativeWorkflow }
                    if ($params.ContainsKey("AllowSavePublishDeclarativeWorkflow")) { $webapp.AllowSavePublishDeclarativeWorkflow = $params.AllowSavePublishDeclarativeWorkflow }
                    if ($params.ContainsKey("AllowSaveDeclarativeWorkflowAsTemplate")) { $webapp.AllowSaveDeclarativeWorkflowAsTemplate = $params.AllowSaveDeclarativeWorkflowAsTemplate }
                    $webapp.Update()
                }
            }
        }
        "SiteCollection" {
            if ((Test-SPDSCRunAsCredential -Credential $InstallAccount) -eq $true) {
                Invoke-SPDSCCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
                    $params = $args[0]

                    try {
                        $spFarm = Get-SPFarm
                    } catch {
                        throw "No local SharePoint farm was detected. SharePoint Designer settings will not be applied"
                        return
                    }
        
                    Write-Verbose -Verbose "Start update SPD site collection settings"

                    # Check if site collection exists
                    $site = Get-SPSite | Where-Object -FilterScript { $_.Url -eq $url }
                    if ($null -eq $site) {
                        throw "Site collection not found. SharePoint Designer settings will not be applied"
                        return $null
                    } else {
                        # Set the SharePoint Designer settings
                        if ($params.ContainsKey("AllowSharePointDesigner")) { $site.AllowDesigner = $params.AllowSharePointDesigner }
                        if ($params.ContainsKey("AllowDetachPagesFromDefinition")) { $site.AllowRevertFromTemplate = $params.AllowDetachPagesFromDefinition }
                        if ($params.ContainsKey("AllowCustomiseMasterPage")) { $site.AllowMasterPageEditing = $params.AllowCustomiseMasterPage }
                        if ($params.ContainsKey("AllowManageSiteURLStructure")) {$site.ShowURLStructure = $params.AllowManageSiteURLStructure }
                        if ($params.ContainsKey("AllowCreateDeclarativeWorkflow")) { $site.AllowCreateDeclarativeWorkflow = $params.AllowCreateDeclarativeWorkflow }
                        if ($params.ContainsKey("AllowSavePublishDeclarativeWorkflow")) { $site.AllowSavePublishDeclarativeWorkflow = $params.AllowSavePublishDeclarativeWorkflow }
                        if ($params.ContainsKey("AllowSaveDeclarativeWorkflowAsTemplate")) { $site.AllowSaveDeclarativeWorkflowAsTemplate = $params.AllowSaveDeclarativeWorkflowAsTemplate }
                    }
                }
            } else {
                throw "A known issue exists that prevents these settings from being managed when InstallAccount is used instead of PsDscRunAsAccount. See http://aka.ms/xSharePointRemoteIssues for details."
            }
        }
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Url,
        [parameter(Mandatory = $true)]  [ValidateSet("WebApplication","SiteCollection")] [System.String] $SettingsScope,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSharePointDesigner,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowDetachPagesFromDefinition,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCustomiseMasterPage,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowManageSiteURLStructure,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowCreateDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSavePublishDeclarativeWorkflow,
        [parameter(Mandatory = $false)] [System.Boolean] $AllowSaveDeclarativeWorkflowAsTemplate,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Testing SharePoint Designer configuration settings"
    $CurrentValues = Get-TargetResource @PSBoundParameters

    if ($null -eq $CurrentValues) { return $false }

    return Test-SPDSCSpecificParameters -CurrentValues $CurrentValues -DesiredValues $PSBoundParameters
}

Export-ModuleMember -Function *-TargetResource
