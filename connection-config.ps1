$script:ecoFlowHosts = [ordered]@{
    eu = 'https://api-e.ecoflow.com'
    us = 'https://api-a.ecoflow.com'
    global = 'https://api.ecoflow.com'
}

function Get-EcoFlowConnection {
    param([Parameter(Mandatory)][string]$Directory)

    $connectionPath = Join-Path $Directory 'connection.xml'
    if (Test-Path -LiteralPath $connectionPath -PathType Leaf) {
        try {
            $saved = Import-Clixml -LiteralPath $connectionPath
            if ($saved.Access -is [pscredential] -and
                $saved.Mode -in @('Private', 'Public') -and
                $saved.Serial -match '^[A-Za-z0-9]+$' -and
                $saved.Host -cin @($script:ecoFlowHosts.Values)) {
                return $saved
            }
        } catch {
            # Windows may be unable to decrypt a connection saved by another user.
        }
    }

    $envPath = Join-Path $Directory '.env'
    if (!(Test-Path -LiteralPath $envPath -PathType Leaf)) { return }

    $settings = @{}
    foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
        if ($line -match '^\s*(ECOFLOW_[A-Z_]+)\s*=(.*)$') {
            $settings[$Matches[1]] = $Matches[2]
        }
    }

    $serial = ([string]$settings.ECOFLOW_SERIAL).Trim()
    $region = ([string]$settings.ECOFLOW_REGION).Trim().ToLowerInvariant()
    $mode = ([string]$settings.ECOFLOW_MODE).Trim()
    if ($serial -notmatch '^[A-Za-z0-9]+$' -or !$script:ecoFlowHosts.Contains($region)) { return }

    switch ($mode) {
        'public' {
            $connectionMode = 'Public'
            $access = ([string]$settings.ECOFLOW_ACCESS_KEY).Trim()
            $secret = [string]$settings.ECOFLOW_SECRET_KEY
        }
        'private' {
            $connectionMode = 'Private'
            $access = ([string]$settings.ECOFLOW_EMAIL).Trim()
            $secret = [string]$settings.ECOFLOW_PASSWORD
        }
        default { return }
    }
    if (!$access -or !$secret) { return }

    [pscustomobject]@{
        Mode = $connectionMode
        Access = [pscredential]::new($access, (ConvertTo-SecureString $secret -AsPlainText -Force))
        Serial = $serial
        Host = $script:ecoFlowHosts[$region]
    }
}
