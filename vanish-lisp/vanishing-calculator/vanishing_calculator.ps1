#!/usr/bin/env pwsh
# Self-Modifying Vanishing Calculator (PowerShell)
# STATE: VISIBLE
# Save and run: pwsh vanishing_calculator.ps1
# Or: powershell -File vanishing_calculator.ps1

$ErrorActionPreference = "Stop"
$ScriptPath = $MyInvocation.MyCommand.Path
if (-not $ScriptPath) { $ScriptPath = $PSCommandPath }

# ============ CALCULATION ENGINE START ============
function Get-Fibonacci {
    param([int]$n)
    if ($n -le 0) { return "[]" }
    if ($n -eq 1) { return "[0]" }
    $a = 0; $b = 1
    $result = "[0, 1"
    for ($i = 2; $i -lt $n; $i++) {
        $c = $a + $b
        $result += ", $c"
        $a = $b; $b = $c
    }
    $result += "]"
    return $result
}

function Get-Primes {
    param([int]$limit)
    if ($limit -lt 2) { return "[]" }
    $sieve = @($true) * ($limit + 1)
    $sieve[0] = $false; $sieve[1] = $false
    for ($i = 2; $i * $i -le $limit; $i++) {
        if ($sieve[$i]) {
            for ($j = $i * $i; $j -le $limit; $j += $i) {
                $sieve[$j] = $false
            }
        }
    }
    $primes = @()
    for ($i = 2; $i -le $limit; $i++) {
        if ($sieve[$i]) { $primes += $i }
    }
    return "[" + ($primes -join ", ") + "]"
}

function Get-Factorial {
    param([int]$n)
    if ($n -lt 0) { return "null" }
    $result = 1
    for ($i = 2; $i -le $n; $i++) {
        $result *= $i
    }
    return $result
}
# ============ CALCULATION ENGINE END ============

function Make-Hidden {
    $content = Get-Content -Raw -Path $ScriptPath
    $startMarker = "# ============ CALCULATION ENGINE START ============"
    $endMarker = "# ============ CALCULATION ENGINE END ============"

    $startIdx = $content.IndexOf($startMarker)
    $endIdx = $content.IndexOf($endMarker)

    if ($startIdx -lt 0 -or $endIdx -lt 0) {
        Write-Error "Could not find markers"
        return
    }

    $before = $content.Substring(0, $startIdx + $startMarker.Length)
    $hiddenSection = $content.Substring($startIdx + $startMarker.Length, $endIdx - $startIdx - $startMarker.Length)
    $after = $content.Substring($endIdx)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hiddenSection)
    $encoded = [Convert]::ToBase64String($bytes)

    $newContent = $before + "`n# [ENGINE HIDDEN - Run again to restore]`n"
    # FIXED (Muse 2026-11-23): the pasted line wrote HIDDEN_PAYLOAD="..." with no $,
    # which PowerShell executes as a command name and fails on the hidden run.
    # A $ variable assignment is the runnable form.
    $newContent += "`$HIDDEN_PAYLOAD=`"$encoded`"`n"
    $newContent += $after
    # FIXED (Muse 2026-11-23): -replace is global and would also rewrite the
    # "# STATE: VISIBLE" strings inside Make-Hidden/Make-Visible themselves.
    # Anchor to the header line only.
    $newContent = $newContent -replace '(?m)^# STATE: VISIBLE', '# STATE: HIDDEN'

    Set-Content -Path $ScriptPath -Value $newContent -NoNewline
    Write-Host ""
    Write-Host "[✓] Rewrote: $ScriptPath"
}

function Make-Visible {
    $content = Get-Content -Raw -Path $ScriptPath
    if ($content -notmatch '\$HIDDEN_PAYLOAD="([^"]+)"') {
        Write-Error "No hidden payload found"
        return
    }
    $encoded = $Matches[1]
    $bytes = [Convert]::FromBase64String($encoded)
    $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)

    $startMarker = "# ============ CALCULATION ENGINE START ============"
    $endMarker = "# ============ CALCULATION ENGINE END ============"

    $startIdx = $content.IndexOf($startMarker)
    $endIdx = $content.IndexOf($endMarker)

    if ($startIdx -lt 0 -or $endIdx -lt 0) {
        Write-Error "Could not find markers"
        return
    }

    $before = $content.Substring(0, $startIdx + $startMarker.Length)
    $after = $content.Substring($endIdx)

    $newContent = $before + $decoded + $after
    $newContent = $newContent -replace '(?m)^# STATE: HIDDEN', '# STATE: VISIBLE'
    $newContent = $newContent -replace '(?m)^\$HIDDEN_PAYLOAD=.*\r?\n', ''

    Set-Content -Path $ScriptPath -Value $newContent -NoNewline
    Write-Host ""
    Write-Host "[✓] Rewrote: $ScriptPath"
}

# RECONSTRUCTED TAIL (Muse 2026-11-23): Main body after the STATE line was cut off in the paste; completed from the same toggle pattern in the other kernels.
function Main {
    $content = Get-Content -Raw -Path $ScriptPath
    Write-Host "======================================================="
    Write-Host " SELF-MODIFYING VANISHING CALCULATOR (POWERSHELL)"
    Write-Host "======================================================="

    # FIXED (Muse 2026-11-23): a whole-file -match always hits, because the
    # toggle code itself contains "# STATE: VISIBLE". Anchor to the header line.
    if ($content -match '(?m)^# STATE: VISIBLE') {
        Write-Host ""
        Write-Host "STATE: VISIBLE - Calculation Engine is ACTIVE"
        Write-Host ""
        Write-Host "Fibonacci(10): $(Get-Fibonacci 10)"
        Write-Host "Primes(30): $(Get-Primes 30)"
        Write-Host "Factorial(5): $(Get-Factorial 5)"
        Make-Hidden
    } else {
        Write-Host ""
        Write-Host "STATE: HIDDEN - Calculation Engine is HIDDEN"
        Make-Visible
        Write-Host "Engine restored. Run again to calculate."
    }
}

Main
