<#
.SYNOPSIS
Collects release-fixed documentation candidates for application-policy review.
.DESCRIPTION
Reads each concrete variant's authoritative property documentation into an
explicit cache and extracts candidate statements mentioning property interaction.
Candidates require review; this command never changes ledgers or runtime policy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)]
    [string]$CacheDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$releaseRoot = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$cacheRoot = [IO.Path]::GetFullPath($CacheDirectory)
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
$results = @()
$previous = @{}
$reportPath = Join-Path $cacheRoot 'documentation-candidates.json'
if (Test-Path -LiteralPath $reportPath) {
    $cached = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    foreach ($variant in $cached.variants) {
        if ($variant.status -ceq 'documentation-collected') { $previous[[string]$variant.id] = $variant }
    }
}

foreach ($file in Get-ChildItem -LiteralPath (Join-Path $releaseRoot 'components') -Filter '*.json' -File | Sort-Object Name) {
    $document = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $id = [string]$document.id
    if ($id -cnotmatch '^[a-z][A-Za-z0-9-]*$') { throw 'Invalid concrete variant cache identity.' }
    $sources = @($document.sources | Where-Object { $_.scope -ceq 'Public properties.' })
    if ($sources.Count -ne 1) { throw "Variant '$id' needs one authoritative property-document source." }
    $url = [uri][string]$sources[0].url
    if ($url.Scheme -cne 'https' -or $url.Host -cne 'www.mathworks.com' -or
            -not $url.AbsolutePath.StartsWith('/help/releases/r2024a/', [StringComparison]::Ordinal)) {
        throw "Variant '$id' has a source outside the approved release-fixed documentation."
    }
    $htmlPath = Join-Path $cacheRoot ($id + '.html')
    try {
        $cacheMatches = (Test-Path -LiteralPath $htmlPath) -and $previous.ContainsKey($id) -and
            $previous[$id].source -ceq $url.AbsoluteUri -and
            $previous[$id].sha256 -ceq (Get-FileHash -LiteralPath $htmlPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($cacheMatches) {
            $html = [IO.File]::ReadAllText($htmlPath)
        }
        else {
            $response = Invoke-WebRequest -Uri $url.AbsoluteUri -TimeoutSec 45
            $html = [string]$response.Content
            [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))
        }
        if (-not $html.Contains('Items') -and -not $html.Contains('Properties')) {
            throw 'The response does not contain a recognizable property reference.'
        }

        # Strip markup as data; do not execute page scripts or source examples.
        $plain = [regex]::Replace($html, '(?is)<(script|style|nav|header|footer)\b[^>]*>.*?</\1>', '')
        $plain = $plain -replace '\s+', ' '
        $plain = [regex]::Replace($plain, '(?i)</?(?:h[1-6]|p|li|tr|div|section)\b[^>]*>', "`n")
        $plain = [regex]::Replace($plain, '(?s)<[^>]*>', '')
        $plain = [Net.WebUtility]::HtmlDecode($plain)
        $lines = @($plain -split '\r?\n' | ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_.Length -gt 0 })
        [IO.File]::WriteAllLines((Join-Path $cacheRoot ($id + '.txt')), [string[]]$lines, [Text.UTF8Encoding]::new($false))
        $paths = @($document.properties | ForEach-Object { [string]$_.path })
        $pattern = '(?<![A-Za-z0-9_])(' + (($paths | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![A-Za-z0-9_])'
        $heading = '^(' + (($paths | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\s*[—–-]'
        $current = ''
        $candidates = @()
        foreach ($line in $lines) {
            $match = [regex]::Match($line, $heading)
            if ($match.Success) { $current = $match.Groups[1].Value }
            $mentioned = @([regex]::Matches($line, $pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -CaseSensitive -Unique)
            if ($mentioned.Count -eq 0 -or $line -notmatch '\b(before|after|depends|setting|set|changes?|changing|automatically|must|when|if|ignored|manual|auto)\b') { continue }
            $other = @($mentioned | Where-Object { $_ -cne $current })
            if ($other.Count -eq 0) { continue }
            $candidates += [ordered]@{ property = $current; mentionedPaths = $mentioned; text = $line }
        }
        $result = [ordered]@{
            id = $id; propertyCount = $paths.Count; status = 'documentation-collected'
            source = $url.AbsoluteUri; sha256 = (Get-FileHash -LiteralPath $htmlPath -Algorithm SHA256).Hash.ToLowerInvariant()
            candidates = $candidates
        }
        $results += $result
        Write-Output ("APPLICATION_DOC {0} Properties={1} Candidates={2}" -f $id, $paths.Count, $candidates.Count)
    }
    catch {
        $results += [ordered]@{ id = $id; status = 'documentation-unavailable'; source = $url.AbsoluteUri; error = $_.Exception.Message }
        Write-Output ("APPLICATION_DOC {0} Unavailable={1}" -f $id, $_.Exception.Message)
    }
}

# Store collection evidence separately from reviewed product policy.
$report = [ordered]@{ artifactVersion = 1; matlabRelease = 'R2024a'; variants = $results }
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 100) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output ("APPLICATION_DOC_SUMMARY Variants={0} Collected={1} Report={2}" -f $results.Count,
    @($results | Where-Object { $_.status -ceq 'documentation-collected' }).Count, $reportPath)
