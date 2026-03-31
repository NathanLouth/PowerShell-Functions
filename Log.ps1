function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [string]$LogDirectory,

        [string]$LogFilePrefix = "ScriptLog",
        [int]$MaxFileSizeMB = 10,
        [int]$MaxTotalSizeMB = 50,
        [bool]$ClearErrors = $true,

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$AdditionalVars
    )

    function Acquire-Lock {
        param(
            [string]$LockFile,
            [int]$RetryDelayMs = 50,
            [int]$MaxWaitMs = 60000
        )

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        while ($true) {
            try {
                # Try to create the lock file exclusively
                $fs = [System.IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None')
                $fs.Close()
                return $true   # Lock acquired
            }
            catch {
                # If we've waited long enough, force-take the lock
                if ($sw.ElapsedMilliseconds -ge $MaxWaitMs) {
                    # Delete stale lock and take it
                    if (Test-Path $LockFile) {
                        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
                    }

                    # Try one last time to create the lock
                    try {
                        $fs = [System.IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None')
                        $fs.Close()
                        return $true
                    }
                    catch {
                        return $false  # Something is seriously wrong
                    }
                }

                Start-Sleep -Milliseconds $RetryDelayMs
            }
        }
    }

    function Release-Lock {
        param([string]$LockFile)
        if (Test-Path $LockFile) {
            Remove-Item $LockFile -Force
        }
    }

    # Ensure log directory exists
    if (-not (Test-Path $LogDirectory)) {
        return
    }

    $lockFile = Join-Path $LogDirectory "$LogFilePrefix.lock"
    $HaveLock = Acquire-Lock -LockFile $lockFile

    if(-not $HaveLock){
        return
    }

    try{
        # Get all log files matching prefix-number.log
        $logFiles = Get-ChildItem -Path $LogDirectory -Filter "$LogFilePrefix-*.log" |
                    Sort-Object LastWriteTime

        # Determine current log file
        if ($logFiles.Count -eq 0) {
            $logFile = Join-Path $LogDirectory "$LogFilePrefix-1.log"
            New-Item -Path $logFile -ItemType File -Force | Out-Null
        } else {
            $logFile = $logFiles[-1].FullName
        }

        # Prepare log line
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $allInfo = $Message

        if ($AdditionalVars) {
            $allInfo += " - " + ($AdditionalVars | ForEach-Object { $_.ToString() } -join " - ")
        }

        $logLine = "[$time] - INFO - $allInfo"

        # Write log entry
        [System.IO.File]::AppendAllText($logFile, $logLine + "`n", [Text.Encoding]::UTF8)

        # Capture local copy of errors to avoid global interference
        $localErrors = $Error.Clone()

        if ($localErrors.Count -gt 0) {
            foreach ($err in $localErrors) {
                $errMsg = if ($err.Exception) { $err.Exception.Message } else { $err.ToString() }
                $errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                [System.IO.File]::AppendAllText($logFile, "[$errTime] - ERROR - $errMsg`n", [Text.Encoding]::UTF8)
            }
            if ($ClearErrors) { $Error.Clear() }
        }

        # Check size AFTER writing
        $maxBytes = $MaxFileSizeMB * 1MB
        if ((Get-Item $logFile).Length -ge $maxBytes) {

            # Determine next index safely
            $logFiles = Get-ChildItem -Path $LogDirectory -Filter "$LogFilePrefix-*.log" |
                        Sort-Object LastWriteTime

            if ($logFiles.Count -eq 0) {
                $nextIndex = 1
            } else {
                $lastName = $logFiles[-1].BaseName -replace "$LogFilePrefix-",""
                $lastIndex = if ($lastName -match '^\d+$') { [int]$lastName } else { 0 }
                $nextIndex = $lastIndex + 1
            }

            # Create new rotated file and switch to it
            $newFile = Join-Path $LogDirectory "$LogFilePrefix-$nextIndex.log"
            New-Item -Path $newFile -ItemType File -Force | Out-Null
            $logFile = $newFile
        }

        # Cleanup old logs if total size exceeds limit
        $allLogs = Get-ChildItem -Path $LogDirectory -Filter "$LogFilePrefix-*.log" |
                Sort-Object LastWriteTime

        $totalSize = ($allLogs | Measure-Object -Property Length -Sum).Sum
        $maxTotalBytes = $MaxTotalSizeMB * 1MB

        while ($totalSize -gt $maxTotalBytes -and $allLogs.Count -gt 1) {
            Remove-Item $allLogs[0].FullName -Force
            $allLogs = Get-ChildItem -Path $LogDirectory -Filter "$LogFilePrefix-*.log" |
                    Sort-Object LastWriteTime
            $totalSize = ($allLogs | Measure-Object -Property Length -Sum).Sum
        }
    }
    finally {
        Release-Lock -LockFile $lockFile
    }
}
