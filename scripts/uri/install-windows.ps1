param(
    [ValidateSet('Install', 'Status', 'Test', 'Uninstall')]
    [string]$Command = 'Status',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$installDir = Join-Path $env:LOCALAPPDATA 'obsidian.nvim'
$launcher = Join-Path $installDir 'obsidian-nvim-uri.ps1'
$nvimConfig = "$launcher.nvim"
$sourceLauncher = Join-Path $PSScriptRoot 'obsidian-nvim-uri.ps1'
$schemeKey = 'HKCU:\Software\Classes\obsidian'
$classesRootCommand = 'Registry::HKEY_CLASSES_ROOT\obsidian\shell\open\command'
$backup = Join-Path $installDir 'obsidian-handler.previous.reg'
$powershell = (Get-Command 'powershell.exe').Source
$handlerCommand = "`"$powershell`" -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" `"%1`""

function Get-CurrentHandler {
    if (Test-Path $classesRootCommand) {
        return (Get-Item $classesRootCommand).GetValue('')
    }
    return $null
}

switch ($Command) {
    'Install' {
        $current = Get-CurrentHandler
        $alreadyInstalled = $current -and $current.Contains($launcher)
        if ($current -and -not $alreadyInstalled -and -not $Force) {
            throw "obsidian:// is currently handled by '$current'. Rerun with -Force to replace it."
        }

        $nvimCommand = if ($env:NVIM) { $env:NVIM } else { 'nvim.exe' }
        $nvimPath = (Get-Command $nvimCommand -ErrorAction Stop).Source
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
        Copy-Item -Force $sourceLauncher $launcher
        Set-Content -NoNewline -Path $nvimConfig -Value $nvimPath

        if ((Test-Path $schemeKey) -and -not $alreadyInstalled) {
            & reg.exe export 'HKCU\Software\Classes\obsidian' $backup /y | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw 'Failed to back up the previous per-user URI handler.'
            }
        }

        New-Item -Force -Path $schemeKey | Out-Null
        Set-Item -Path $schemeKey -Value 'URL:Obsidian Protocol'
        New-ItemProperty -Force -Path $schemeKey -Name 'URL Protocol' -Value '' | Out-Null
        $commandKey = New-Item -Force -Path (Join-Path $schemeKey 'shell\open\command')
        Set-Item -Path $commandKey.PSPath -Value $handlerCommand
        Write-Output "Installed obsidian:// handler: $launcher"
    }
    'Status' {
        $current = Get-CurrentHandler
        Write-Output "Current obsidian:// handler: $(if ($current) { $current } else { 'none' })"
        if (-not ($current -and $current.Contains($launcher))) {
            exit 1
        }
    }
    'Test' {
        Start-Process 'obsidian://choose-vault'
    }
    'Uninstall' {
        if (Test-Path $schemeKey) {
            Remove-Item -Recurse -Force $schemeKey
        }
        if (Test-Path $backup) {
            & reg.exe import $backup | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw 'Failed to restore the previous URI handler.'
            }
        }
        Remove-Item -Force -ErrorAction SilentlyContinue $launcher, $nvimConfig, $backup
        Write-Output 'Removed the per-user obsidian.nvim URI handler.'
    }
}
