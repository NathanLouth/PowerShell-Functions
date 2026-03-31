function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogFile,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [bool]$ClearErrors = $true,

        [int]$MaxLines = 100000,       # Max lines before trimming
        [int]$TrimLines = 1000,        # Number of lines to remove when trimming

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$AdditionalVars
    )

    # -------------------------------
    # Ensure log directory exists
    # -------------------------------
    $logDir = Split-Path $LogFile
    if (-not (Test-Path $logDir)) {
        return
    }

    # -------------------------------
    # Create log file if it doesn't exist
    # -------------------------------
    if (-not (Test-Path $LogFile)) {
        New-Item -Path $LogFile -ItemType File | Out-Null
    }

    # -------------------------------
    # Prepare log line
    # -------------------------------
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $allInfo = if ($AdditionalVars -and $AdditionalVars.Count -gt 0) {
        "$Message - " + ($AdditionalVars -join " - ")
    } else {
        $Message
    }

    $logLine = "[$time] - INFO - $allInfo"

    # -------------------------------
    # Append log line using StreamWriter
    # -------------------------------
    $stream = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
    try {
        $stream.WriteLine($logLine)

        # -------------------------------
        # Log last error if any
        # -------------------------------
        if ($Error.Count -gt 0) {
            $lastError = $Error[0]
            $errorLine = "[$time] - ERROR - $($lastError.Exception.Message)"
            $stream.WriteLine($errorLine)

            if ($ClearErrors) { $Error.Clear() }
        }
    } finally {
        $stream.Close()
    }

    # -------------------------------
    # Trim the log if needed
    # -------------------------------
    $linesToKeep = [Math]::Max(0, $MaxLines - $TrimLines)

    # Only perform trimming if needed
    if ((Get-Content $LogFile -ReadCount 0).Count -ge $MaxLines) {

        # Use a rolling queue to keep memory usage low
        $queue = New-Object System.Collections.Generic.Queue[string]

        foreach ($line in [System.IO.File]::ReadLines($LogFile)) {
            $queue.Enqueue($line)
            if ($queue.Count -gt $linesToKeep) {
                $queue.Dequeue()
            }
        }

        # Write only the newest $linesToKeep lines back to the log
        [System.IO.File]::WriteAllLines($LogFile, $queue)

        # -------------------------------
        # Log trimming activity
        # -------------------------------
        using ($stream = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)) {
            $stream.WriteLine("[$time] - LOG - Trimmed $TrimLines oldest lines")
        }
    }
}
