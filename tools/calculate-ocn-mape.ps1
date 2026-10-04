[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$CeIpv6,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# OCN Virtual Connect rule snapshot, verified against the 2026-10-01 direct
# CE address observed on this line. It is deliberately narrow: fail closed if
# OCN assigns a prefix outside this rule instead of selecting a guessed rule.
$Rules = @(
    [pscustomobject]@{
        Ipv6Prefix = '2400:4050:8000::'
        Ipv6PrefixLength = 33
        Ipv4Prefix = '153.242.0.0'
        Ipv4PrefixLength = 15
        EaBitsLength = 23
        PsidOffset = 6
        BrIpv6Address = '2001:380:a120::9'
    }
)

function ConvertTo-IPv6Bytes([string]$Value) {
    $address = [System.Net.IPAddress]::Parse(($Value -split '/')[0])
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        throw "CE address is not IPv6: $Value"
    }
    return $address.GetAddressBytes()
}

function Test-IPv6Prefix([byte[]]$Address, [byte[]]$Prefix, [int]$Length) {
    $fullBytes = [math]::Floor($Length / 8)
    for ($index = 0; $index -lt $fullBytes; $index++) {
        if ($Address[$index] -ne $Prefix[$index]) { return $false }
    }
    $remaining = $Length % 8
    if ($remaining -eq 0) { return $true }
    $mask = [byte]((0xFF -shl (8 - $remaining)) -band 0xFF)
    return (($Address[$fullBytes] -band $mask) -eq ($Prefix[$fullBytes] -band $mask))
}

function Get-Bits([byte[]]$Bytes, [int]$Start, [int]$Length) {
    [UInt64]$value = 0
    for ($index = $Start; $index -lt ($Start + $Length); $index++) {
        $byteIndex = [math]::Floor($index / 8)
        $bitIndex = 7 - ($index % 8)
        $value = ($value -shl 1) -bor (($Bytes[$byteIndex] -shr $bitIndex) -band 1)
    }
    return $value
}

function ConvertFrom-IPv4Integer([UInt64]$Value) {
    return '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 0xFF), (($Value -shr 16) -band 0xFF), (($Value -shr 8) -band 0xFF), ($Value -band 0xFF)
}

$ceBytes = ConvertTo-IPv6Bytes $CeIpv6
$rule = $Rules | Where-Object {
    Test-IPv6Prefix $ceBytes (ConvertTo-IPv6Bytes $_.Ipv6Prefix) $_.Ipv6PrefixLength
} | Select-Object -First 1

if ($null -eq $rule) {
    throw "No local OCN MAP-E rule matches $CeIpv6. Do not configure MAP-E; add a newly verified rule snapshot first."
}

$ipv4SuffixLength = 32 - $rule.Ipv4PrefixLength
$psidLength = $rule.EaBitsLength - $ipv4SuffixLength
if ($psidLength -lt 0 -or $rule.PsidOffset + $psidLength -gt 16) {
    throw "Invalid local rule: EA bits/IPv4 prefix/offset are inconsistent."
}

$eaValue = Get-Bits $ceBytes $rule.Ipv6PrefixLength $rule.EaBitsLength
[UInt64]$ipv4Suffix = $eaValue -shr $psidLength
[UInt64]$psidMask = ([UInt64]1 -shl $psidLength) - 1
[UInt64]$psid = $eaValue -band $psidMask
$ipv4PrefixBytes = [System.Net.IPAddress]::Parse($rule.Ipv4Prefix).GetAddressBytes()
[UInt64]$ipv4PrefixValue = 0
foreach ($octet in $ipv4PrefixBytes) { $ipv4PrefixValue = ($ipv4PrefixValue -shl 8) -bor $octet }
[UInt64]$ipv4Value = $ipv4PrefixValue -bor $ipv4Suffix
$portWidth = 16 - $rule.PsidOffset - $psidLength
$portSetSize = [UInt64]1 -shl $portWidth
$portSetStep = [UInt64]1 -shl ($psidLength + $portWidth)
$portSetCount = [UInt64]1 -shl $rule.PsidOffset
[UInt64]$firstPort = $psid -shl $portWidth
$portRanges = for ([UInt64]$index = 1; $index -lt $portSetCount; $index++) {
    $start = $firstPort + ($index * $portSetStep)
    [pscustomobject]@{ Start = $start; End = $start + $portSetSize - 1 }
}

$mapRule = 'type=map-e,ipv6prefix={0},prefix6len={1},ipv4prefix={2},prefix4len={3},ealen={4},offset={5},br={6}' -f $rule.Ipv6Prefix, $rule.Ipv6PrefixLength, $rule.Ipv4Prefix, $rule.Ipv4PrefixLength, $rule.EaBitsLength, $rule.PsidOffset, $rule.BrIpv6Address

$result = [ordered]@{
    ce_ipv6 = ([System.Net.IPAddress]::new($ceBytes)).ToString()
    rule_ipv6_prefix = "$($rule.Ipv6Prefix)/$($rule.Ipv6PrefixLength)"
    rule_ipv4_prefix = "$($rule.Ipv4Prefix)/$($rule.Ipv4PrefixLength)"
    br_ipv6 = $rule.BrIpv6Address
    ea_bits_length = $rule.EaBitsLength
    psid_offset = $rule.PsidOffset
    psid_length = $psidLength
    psid = $psid
    derived_ipv4 = ConvertFrom-IPv4Integer $ipv4Value
    port_ranges = $portRanges
    map_rule = $mapRule
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 4
    exit 0
}

$result.GetEnumerator() | Where-Object { $_.Key -ne 'port_ranges' } | ForEach-Object {
    '{0}={1}' -f $_.Key, $_.Value
}
'port_ranges='
$portRanges | ForEach-Object { '  {0}-{1}' -f $_.Start, $_.End }
