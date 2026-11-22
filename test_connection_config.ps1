$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'connection-config.ps1')

$directory = Join-Path ([IO.Path]::GetTempPath()) ('river-config-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($directory)
$envPath = Join-Path $directory '.env'
$connectionPath = Join-Path $directory 'connection.xml'

try {
    if (Get-EcoFlowConnection $directory) { throw 'A clean checkout should start unconfigured.' }
    @'
ECOFLOW_MODE=private
ECOFLOW_REGION=us
ECOFLOW_SERIAL=DEMO123
ECOFLOW_EMAIL=demo@example.com
ECOFLOW_PASSWORD=fixture=with#punctuation
'@ | Set-Content -LiteralPath $envPath -Encoding UTF8
    $config = Get-EcoFlowConnection $directory
    if ($config.Mode -ne 'Private' -or $config.Host -ne $script:ecoFlowHosts.us -or
        $config.Serial -ne 'DEMO123' -or $config.Access.UserName -ne 'demo@example.com' -or
        $config.Access.GetNetworkCredential().Password -ne 'fixture=with#punctuation') {
        throw 'Private .env configuration was not read correctly.'
    }

    $saved = [pscustomobject]@{
        Mode = 'Public'
        Serial = 'SAVEDTEST'
        Host = $script:ecoFlowHosts.global
        Access = [pscredential]::new('saved-fixture', (ConvertTo-SecureString 'fixture' -AsPlainText -Force))
    }
    $saved | Export-Clixml -LiteralPath $connectionPath
    if ((Get-EcoFlowConnection $directory).Serial -ne $saved.Serial) {
        throw 'Saved connections should take precedence over .env.'
    }
    $saved.Host = 'https://example.com'
    $saved | Export-Clixml -LiteralPath $connectionPath
    if ((Get-EcoFlowConnection $directory).Serial -ne 'DEMO123') {
        throw 'Connections with an unknown host should be rejected.'
    }
    @'
ECOFLOW_MODE=public
ECOFLOW_REGION=eu
ECOFLOW_SERIAL=DEMO456
ECOFLOW_ACCESS_KEY=fixture-access
ECOFLOW_SECRET_KEY=fixture-secret
'@ | Set-Content -LiteralPath $envPath -Encoding UTF8
    $config = Get-EcoFlowConnection $directory
    if ($config.Mode -ne 'Public' -or $config.Host -ne $script:ecoFlowHosts.eu -or
        $config.Access.UserName -ne 'fixture-access') {
        throw 'Public .env configuration was not read correctly.'
    }
    'PASS: clean startup, .env modes, saved connection precedence, host allowlist'
} finally {
    Remove-Item -LiteralPath $envPath, $connectionPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $directory -ErrorAction SilentlyContinue
}
