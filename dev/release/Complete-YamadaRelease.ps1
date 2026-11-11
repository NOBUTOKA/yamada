# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Artifact,
    [Parameter(Mandatory)] [string] $SigningKey
)
$ErrorActionPreference = 'Stop'
$artifactPath = (Resolve-Path -LiteralPath $Artifact).Path
$folder = Split-Path -Parent $artifactPath
$manifest = Get-Content -LiteralPath (Join-Path $folder 'build-manifest.json') -Raw | ConvertFrom-Json
$metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolbox.json') -Raw | ConvertFrom-Json
$expectedName = 'yamada-' + $metadata.version + '.mltbx'
if ((Split-Path -Leaf $artifactPath) -ne $expectedName -or $manifest.version -ne $metadata.version -or $manifest.identifier -ne $metadata.identifier) {
    throw 'The artifact, build manifest, and release metadata do not agree.'
}
if ($manifest.sourceDirty) { throw 'Do not sign a build from a dirty checkout. Build again from the final signed commit.' }
if ($manifest.sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'The manifest does not identify a valid source commit.' }
$actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $manifest.toolboxSha256) { throw 'The artifact differs from the build manifest.' }
$checksumPath = Join-Path $folder 'SHA256SUMS'
$expectedChecksum = $actualHash + '  ' + $expectedName
if ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -ne $expectedChecksum) { throw 'SHA256SUMS does not match the artifact.' }

# Require the recorded release commit to carry a valid GPG signature.
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
& git -C $repository verify-commit $manifest.sourceCommit
if ($LASTEXITCODE -ne 0) { throw 'The release source commit does not have a verifiable GPG signature.' }
& git -C $repository merge-base --is-ancestor $manifest.sourceCommit main
if ($LASTEXITCODE -ne 0) { throw 'The release source commit has not been integrated into main.' }

# Keep signed outputs fixed and let GnuPG request hardware interaction itself.
$signature = $artifactPath + '.asc'
if (Test-Path -LiteralPath $signature) { throw 'A signature already exists; refusing to replace it.' }
& gpg --local-user $SigningKey --armor --output $signature --detach-sign $artifactPath
if ($LASTEXITCODE -ne 0) { throw 'GPG signing failed. Do not publish the output.' }
& gpg --verify $signature $artifactPath
if ($LASTEXITCODE -ne 0) { throw 'GPG signature verification failed. Do not publish the output.' }
if ((Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $actualHash) {
    throw 'The artifact changed during signing. Do not publish the output.'
}
Write-Output "Release assets prepared: $artifactPath, $signature, $checksumPath"
