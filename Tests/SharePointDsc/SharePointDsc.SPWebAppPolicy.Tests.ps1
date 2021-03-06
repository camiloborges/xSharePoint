[CmdletBinding()]
param(
    [string] $SharePointCmdletModule = (Join-Path $PSScriptRoot "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" -Resolve)
)

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..).Path
$Global:CurrentSharePointStubModule = $SharePointCmdletModule

$ModuleName = "MSFT_SPWebAppPolicy"
Import-Module (Join-Path $RepoRoot "Modules\SharePointDsc\DSCResources\$ModuleName\$ModuleName.psm1") -Force

Describe "SPWebAppPolicy - SharePoint Build $((Get-Item $SharePointCmdletModule).Directory.BaseName)" {
    InModuleScope $ModuleName {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $true
                    } -ClientOnly)
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user2"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }

        Import-Module (Join-Path ((Resolve-Path $PSScriptRoot\..\..).Path) "Modules\SharePointDsc")
        
        Remove-Module -Name "Microsoft.SharePoint.PowerShell" -Force -ErrorAction SilentlyContinue
        Import-Module $Global:CurrentSharePointStubModule -WarningAction SilentlyContinue

        Mock Invoke-SPDSCCommand { 
            return Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Arguments -NoNewScope
        }

        Mock Test-SPDSCIsADUser {
            return $true
        }

        Mock New-SPClaimsPrincipal { 
            return @{
                Value = $Identity -replace "i:0#.w\|"
            }
        } -ParameterFilter { $IdentityType -eq "EncodedClaim" }

        Mock New-SPClaimsPrincipal { 
            $Global:SPDSCClaimsPrincipalUser = $Identity
            return (
                New-Object Object | Add-Member ScriptMethod ToEncodedString { 
                    return "i:0#.w|$($Global:SPDSCClaimsPrincipalUser)" 
                } -PassThru
            )
        } -ParameterFilter { $IdentityType -eq "WindowsSamAccountName" }

        Mock Remove-SPDSCGenericObject { }
        
        try { [Microsoft.SharePoint.Administration.SPPolicyRoleType] }
        catch {
            Add-Type @"
namespace Microsoft.SharePoint.Administration {
    public enum SPPolicyRoleType { FullRead, FullControl, DenyWrite, DenyAll };
}        
"@
        }  


        Context "The web application doesn't exist" {
            Mock Get-SPWebApplication { return $null }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "returns null from the set method" {
                { Set-TargetResource @testParams } | Should throw "Web application does not exist"
            }
        }
        
        Context "Members and MembersToInclude parameters used simultaniously" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }

            It "return null from the get method" {
                Get-TargetResource @testParams | Should Be $null
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "should throw an exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "Cannot use the Members parameter together with the MembersToInclude or MembersToExclude parameters"
            }
        }
        
        Context "No Member parameters at all" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
            }

            It "return null from the get method" {
                Get-TargetResource @testParams | Should Be $null
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "should throw an exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "At least one of the following parameters must be specified: Members, MembersToInclude, MembersToExclude"
            }
        }
        
        Context "ActAsSystemAccount parameter specified without Full Control in Members" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $true
                    } -ClientOnly)
                )
            }

            It "return null from the get method" {
                Get-TargetResource @testParams | Should Be $null
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "should throw an exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "Members Parameter: You cannot specify ActAsSystemAccount with any other permission than Full Control"
            }
        }

        Context "ActAsSystemAccount parameter specified without Full Control in MembersToInclude" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $true
                    } -ClientOnly)
                )
            }

            It "return null from the get method" {
                Get-TargetResource @testParams | Should Be $null
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "should throw an exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "MembersToInclude Parameter: You cannot specify ActAsSystemAccount with any other permission than Full Control"
            }
        }

        Context "The Members parameter used with SetCacheAccounts to True, but the Cache Users users aren't configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                        portalsuperuseraccount = "contoso\sp_psu"
                        portalsuperreaderaccount = "contoso\sp_psr"
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "add user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The MembersToInclude parameter used with SetCacheAccounts to True, but the Cache Users users aren't configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                        portalsuperuseraccount = "contoso\sp_psu"
                        portalsuperreaderaccount = "contoso\sp_psr"
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "add user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The Members parameter used with SetCacheAccounts to True, but the Cache Users users aren't configured in the webapp" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "should throw exception in the test method" {
                { Test-TargetResource @testParams } | Should throw "Cache accounts not configured properly. PortalSuperUserAccount or PortalSuperReaderAccount property is not configured."
            }

            It "should throw exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "Cache accounts not configured properly. PortalSuperUserAccount or PortalSuperReaderAccount property is not configured."
            }
        }

        Context "The MembersToInclude parameter used with SetCacheAccounts to True, but the Cache Users users aren't configured in the webapp" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "should throw exception in the test method" {
                { Test-TargetResource @testParams } | Should throw "Cache accounts not configured properly. PortalSuperUserAccount or PortalSuperReaderAccount property is not configured."
            }

            It "should throw exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "Cache accounts not configured properly. PortalSuperUserAccount or PortalSuperReaderAccount property is not configured."
            }
        }

        Context "The Members parameter used with SetCacheAccounts to True and the Cache Users users are configured correctly" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindingsFR = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindingsFR = $roleBindingsFR | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $roleBindingsFC = @(
                    @{
                        Name = "Full Control"
                    }
                )
                $roleBindingsFC = $roleBindingsFC | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "i:0#.w|contoso\sp_psu"
                        PolicyRoleBindings = $roleBindingsFC
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "i:0#.w|contoso\sp_psr"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                        portalsuperuseraccount = "i:0#.w|contoso\sp_psu"
                        portalsuperreaderaccount = "i:0#.w|contoso\sp_psr"
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns true from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The MembersToInclude parameter used with SetCacheAccounts to True and the Cache Users users are configured correctly" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
                SetCacheAccounts=$true
            }
            Mock Get-SPWebApplication { 
                $roleBindingsFR = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindingsFR = $roleBindingsFR | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $roleBindingsFC = @(
                    @{
                        Name = "Full Control"
                    }
                )
                $roleBindingsFC = $roleBindingsFC | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "i:0#.w|contoso\sp_psu"
                        PolicyRoleBindings = $roleBindingsFC
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "i:0#.w|contoso\sp_psr"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                        portalsuperuseraccount = "contoso\sp_psu"
                        portalsuperreaderaccount = "contoso\sp_psr"
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The MembersToExclude parameter used, but it specifies a Cache User" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToExclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\sp_psr"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindingsFR = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindingsFR = $roleBindingsFR | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $roleBindingsFC = @(
                    @{
                        Name = "Full Control"
                    }
                )
                $roleBindingsFC = $roleBindingsFC | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "contoso\sp_psu"
                        PolicyRoleBindings = $roleBindingsFC
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "contoso\sp_psr"
                        PolicyRoleBindings = $roleBindingsFR
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{
                        portalsuperuseraccount = "contoso\sp_psu"
                        portalsuperreaderaccount = "contoso\sp_psr"
                    }
                }
                
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "should throw exception in the test method" {
                { Test-TargetResource @testParams } | Should throw "You cannot exclude the Cache accounts from the Web Application Policy"
            }

            It "should throw exception in the set method" {
                { Set-TargetResource @testParams } | Should throw "You cannot exclude the Cache accounts from the Web Application Policy"
            }
        }

        Context "The Members parameter contains users that aren't configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user2"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the set method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "add user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The Members parameter does not contains users that are configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "i:0#.w|contoso\user2"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                ) | Add-Member -MemberType ScriptMethod -Name Add -Value { param($input) return $null } -Force -PassThru
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "remove user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The MembersToInclude parameter contains users that are not configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user2"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "add user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The MembersToInclude parameter contains users that are configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Read"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    },
                    @{
                        UserName = "i:0#.w|contoso\user2"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )

                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }



            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The MembersToExclude parameter contains users that are configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToExclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                    @{
                        UserName = "contoso\user2"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru | 
                Add-Member NoteProperty Properties @{} -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "remove user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The users in the Members parameter have different settings than configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru
                $roleBindings = $roleBindings | Add-Member ScriptMethod Add {
                    $Global:SPWebAppPolicyAddCalled = $true
                } -PassThru -Force

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "correct user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The users in the MembersToInclude parameter have different settings than configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Read"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru
                $roleBindings = $roleBindings | Add-Member ScriptMethod Add {
                    $Global:SPWebAppPolicyAddCalled = $true
                } -PassThru -Force

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "correct user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The users in the Members parameter have different settings than configured in the policy - ActAsSystemAccount" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $true
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru
                $roleBindings = $roleBindings | Add-Member ScriptMethod Add {
                    $Global:SPWebAppPolicyAddCalled = $true
                } -PassThru -Force

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "correct user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The users in the MembersToInclude parameter have different settings than configured in the policy - ActAsSystemAccount" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $true
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )
                $roleBindings = $roleBindings | Add-Member ScriptMethod RemoveAll {
                    $Global:SPWebAppPolicyRemoveAllCalled = $true
                } -PassThru
                $roleBindings = $roleBindings | Add-Member ScriptMethod Add {
                    $Global:SPWebAppPolicyAddCalled = $true
                } -PassThru -Force

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                $policies = $policies | Add-Member ScriptMethod Add {
                    $policy = @{
                        IsSystemUser = $false
                    }
                    $policy = $policy | Add-Member ScriptProperty PolicyRoleBindings {
                        return New-Object Object | Add-Member ScriptMethod Add {} -PassThru
                    } -PassThru
                    return $policy
                } -PassThru -Force
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                $webApp = $webApp | Add-Member ScriptMethod Update {
                    $Global:SPWebApplicationUpdateCalled = $true
                } -PassThru
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }

            $Global:SPWebApplicationUpdateCalled = $false
            It "correct user policy from the set method" {
                Set-TargetResource @testParams
                $Global:SPWebApplicationUpdateCalled | Should Be $true
            }
        }

        Context "The users in the Members parameter have the same settings as configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                        IdentityType       = "Native"
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The users in the Members parameter have the same settings as configured in the policy, in Claims format" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                        IdentityType       = "Claims"
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The users in the MembersToInclude parameter have the same  settings as configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToInclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )

                $policies = @(
                    @{
                        UserName = "i:0#.w|contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The users in the MembersToExclude parameter aren't configured in the policy" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                MembersToExclude = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\user2"
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )

                $policies = @(
                    @{
                        UserName = "contoso\user1"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "The users in the Members parameter have the same settings as configured in the policy, in Claims format with a windows group in the results" {
            $testParams = @{
                WebAppUrl   = "http://sharepoint.contoso.com"
                Members = @(
                    (New-CimInstance -ClassName MSFT_SPWebAppPolicy -Property @{
                        Username           = "contoso\group1"
                        PermissionLevel    = "Full Control"
                        ActAsSystemAccount = $false
                        IdentityType       = "Claims"
                    } -ClientOnly)
                )
            }
            Mock Get-SPWebApplication { 
                $roleBindings = @(
                    @{
                        Name = "Full Control"
                    }
                )

                $policies = @(
                    @{
                        UserName = "i:0#.w|s-1-5-21-2753725054-2932589700-2007370523-2138"
                        PolicyRoleBindings = $roleBindings
                        IsSystemUser = $false
                    }   
                )
                 
                $webApp = @{
                    Url = $testParams.WebAppUrl
                    UseClaimsAuthentication = $true
                    PolicyRoles = New-Object Object |
                                    Add-Member ScriptMethod GetSpecialRole { return @{} } -PassThru
                    Policies = $policies
                    Properties = @{}
                }
                return @($webApp)
            }
            Mock Resolve-SPDscSecurityIdentifier {
                return "contoso\group1"
            }

            It "returns null from the get method" {
                Get-TargetResource @testParams | Should Not BeNullOrEmpty
            }

            It "returns false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }
    }    
}
