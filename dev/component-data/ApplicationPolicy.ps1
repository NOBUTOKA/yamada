# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

<#
.SYNOPSIS
Validates and normalizes declarative property application policies.
.DESCRIPTION
Shared by grouping and promotion so initialization rules participate in
capability identity without conflating them with validation or display order.
#>

function ConvertTo-ApplicationPolicy {
    param([object]$Policy, [string]$Context = 'application')

    if ($null -eq $Policy -or $Policy -isnot [pscustomobject]) {
        throw "$Context must be an application policy object."
    }
    foreach ($field in @($Policy.PSObject.Properties | ForEach-Object Name)) {
        if ($field -notin @('applyAfter', 'effectPolicy', 'defaultLiteral', 'effectStatus', 'affectedPaths', 'effectReason')) {
            throw "$Context contains unknown field '$field'."
        }
    }
    $dependencies = @()
    if ($null -ne $Policy.PSObject.Properties['applyAfter']) {
        if ($Policy.applyAfter -isnot [array]) {
            throw "$Context.applyAfter must be a string array."
        }
        foreach ($path in $Policy.applyAfter) {
            if ($path -isnot [string] -or $path -cnotmatch '^[A-Za-z]\w*(\.[A-Za-z]\w*)*$') {
                throw "$Context.applyAfter contains an invalid property path."
            }
            if ($dependencies -ccontains $path) {
                throw "$Context.applyAfter contains duplicate '$path'."
            }
            $dependencies += $path
        }
    }
    $effect = 'none'
    if ($null -ne $Policy.PSObject.Properties['effectPolicy']) {
        $effect = $Policy.effectPolicy
    }
    if ($effect -isnot [string] -or $effect -cnotin @('none', 'itemSelection', 'boundedValue',
            'numericValue', 'tickMode', 'valueMode', 'modeFlag', 'axisWidth', 'positionAlias', 'squarePositionAlias',
            'textValue', 'componentReference', 'layout', 'gridTracks', 'buttonSelection', 'positionInput', 'sliderPosition', 'squarePosition', 'switchPosition', 'semicircularPosition', 'linearPosition')) {
        throw "$Context.effectPolicy has an unknown effect policy."
    }
    $result = [ordered]@{
        applyAfter = @($dependencies | Sort-Object -CaseSensitive)
        effectPolicy = $effect
    }
    if ($null -ne $Policy.PSObject.Properties['defaultLiteral']) {
        if ($Policy.defaultLiteral -isnot [string] -or [string]::IsNullOrWhiteSpace($Policy.defaultLiteral)) {
            throw "$Context.defaultLiteral must be a nonempty inert MATLAB literal string."
        }
        $result.defaultLiteral = $Policy.defaultLiteral
    }
    $status = 'unknown'
    if ($null -ne $Policy.PSObject.Properties['effectStatus']) { $status = $Policy.effectStatus }
    if ($status -isnot [string] -or $status -cnotin @('unknown', 'independent', 'modeled', 'unsupported')) {
        throw "$Context.effectStatus is invalid."
    }
    $result.effectStatus = $status
    $affected = @()
    if ($null -ne $Policy.PSObject.Properties['affectedPaths']) {
        if ($Policy.affectedPaths -isnot [array]) { throw "$Context.affectedPaths must be an array." }
        foreach ($path in $Policy.affectedPaths) {
            if ($path -isnot [string] -or $path -cnotmatch '^[A-Za-z]\w*(\.[A-Za-z]\w*)*$' -or $affected -ccontains $path) {
                throw "$Context.affectedPaths must contain unique property paths."
            }
            $affected += $path
        }
    }
    $result.affectedPaths = @($affected | Sort-Object -CaseSensitive)
    if ($null -ne $Policy.PSObject.Properties['effectReason']) {
        if ($Policy.effectReason -isnot [string] -or [string]::IsNullOrWhiteSpace($Policy.effectReason)) {
            throw "$Context.effectReason must be a nonempty explanation."
        }
        $result.effectReason = $Policy.effectReason
    }
    return $result
}

function Test-ApplicationPolicies {
    param([object[]]$Properties, [string]$Context)

    # Check the concrete surface after normalization, never reusable fragments.
    $remaining = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($property in $Properties) {
        $remaining.Add([string]$property.path, @())
    }
    foreach ($property in $Properties) {
        if ($null -eq $property.PSObject.Properties['application']) { continue }
        $policy = ConvertTo-ApplicationPolicy $property.application "$Context.$($property.path).application"
        foreach ($target in $policy.affectedPaths) {
            if (-not $remaining.ContainsKey($target)) { throw "$Context names missing affected path '$target'." }
        }
        foreach ($target in $policy.applyAfter) {
            if (-not $remaining.ContainsKey($target)) {
                throw "$Context.$($property.path) names missing application dependency '$target'."
            }
            if ($target -ceq [string]$property.path) {
                throw "$Context.$target has a self-referential application dependency."
            }
        }
        $remaining[[string]$property.path] = @($policy.applyAfter)
    }
    while ($remaining.Count -gt 0) {
        $ready = @($remaining.Keys | Where-Object { $remaining[$_].Count -eq 0 })
        if ($ready.Count -eq 0) { throw "$Context contains cyclic application dependencies." }
        foreach ($path in $ready) { $null = $remaining.Remove($path) }
        foreach ($path in @($remaining.Keys)) {
            $remaining[$path] = @($remaining[$path] | Where-Object { $ready -cnotcontains $_ })
        }
    }
}
