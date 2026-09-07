param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Uri
)

$ErrorActionPreference = 'Stop'
if ($Uri -notmatch '^obsidian://') {
    throw "Expected an obsidian:// URI"
}

$nvimConfig = "$PSCommandPath.nvim"
$nvim = if ($env:NVIM) {
    $env:NVIM
} elseif (Test-Path $nvimConfig) {
    (Get-Content -Raw $nvimConfig).Trim()
} else {
    'nvim.exe'
}
if (-not (Get-Command $nvim -ErrorAction SilentlyContinue)) {
    throw "Neovim executable not found: $nvim"
}

$env:OBSIDIAN_NVIM_URI = $Uri
$luaCommand = "+lua local r=require('obsidian.uri').handle(vim.env.OBSIDIAN_NVIM_URI); vim.g.obsidian_uri_failed=not r.ok"
$quitCommand = "+lua if vim.g.obsidian_uri_failed then vim.cmd('cquit') else vim.cmd('quitall') end"
$isSilent = $Uri -match '^obsidian://(?:new|daily)\?' -and $Uri -match '(?:[?&])silent(?:=|&|$)'

if ($isSilent) {
    & $nvim --headless $luaCommand $quitCommand
    exit $LASTEXITCODE
}

$windowsTerminal = Get-Command 'wt.exe' -ErrorAction SilentlyContinue
if ($windowsTerminal) {
    & $windowsTerminal.Source new-tab -- $nvim $luaCommand
    exit $LASTEXITCODE
}

Start-Process -FilePath $nvim -ArgumentList @($luaCommand)
