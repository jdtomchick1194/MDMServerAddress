# Run as SYSTEM using 64-bit Windows PowerShell. Sensor return type: String.
$ErrorActionPreference = 'Stop'

if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    throw 'Run this script using 64-bit PowerShell.'
}

if (-not ('WorkspaceOneMdm.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WorkspaceOneMdm
{
    public static class NativeMethods
    {
        [DllImport("MDMRegistration.dll", CharSet = CharSet.Unicode,
            ExactSpelling = true)]
        public static extern int IsDeviceRegisteredWithManagement(
            [MarshalAs(UnmanagedType.Bool)] out bool isRegistered,
            uint upnLength,
            StringBuilder upn);
    }
}
'@
}

$isRegistered = $false
$result = [WorkspaceOneMdm.NativeMethods]::IsDeviceRegisteredWithManagement(
    [ref]$isRegistered, 0, $null
)
if ($result -lt 0) {
    [Runtime.InteropServices.Marshal]::ThrowExceptionForHR($result)
}

if (-not $isRegistered) {
    Write-Output 'Not MDM managed'
    return
}

# Read the OMA-DM management endpoint, not the enrollment/discovery URL.
$accountsPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
$addresses = @(
    Get-ChildItem -LiteralPath $accountsPath | ForEach-Object {
        $addressPath = "$($_.PSPath)\Protected\AddrInfo"
        if (-not (Test-Path -LiteralPath $addressPath)) {
            return
        }
        $account = Get-ItemProperty -LiteralPath $addressPath
        $address = $account.PSObject.Properties['Addr']
        if ($null -ne $address -and
            -not [string]::IsNullOrWhiteSpace([string]$address.Value)) {
            ([string]$address.Value).Trim()
        }
    } | Sort-Object -Unique
)

if ($addresses.Count -eq 0) {
    throw 'Windows reports MDM enrollment, but no management address was found.'
}
Write-Output ($addresses -join '; ')
