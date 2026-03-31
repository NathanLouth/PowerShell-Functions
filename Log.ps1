function Write-Log {
    [CmdletBinding()]
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
        New-Item -Path $logDir -ItemType Directory | Out-Null
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
    if (Test-Path $LogFile) {
        $linesToKeep = $MaxLines - $TrimLines

        # Read only the last $MaxLines lines lazily
        $tailLines = [System.IO.File]::ReadLines($LogFile) | Select-Object -Last $MaxLines

        if ($tailLines.Count -ge $MaxLines) {
            # Keep only the newest lines
            $linesToKeepArray = $tailLines | Select-Object -Last $linesToKeep
            [System.IO.File]::WriteAllLines($LogFile, $linesToKeepArray)

            # -------------------------------
            # Log trimming activity
            # -------------------------------
            $stream = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
            try {
                $stream.WriteLine("[$time] - LOG - Trimmed $TrimLines oldest lines")
            } finally {
                $stream.Close()
            }
        }
    }
}
