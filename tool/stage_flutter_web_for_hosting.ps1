$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$buildWebDir = Join-Path $projectRoot "build\web"
$hostingAppDir = Join-Path $projectRoot "hosting\app"

if (-not (Test-Path $buildWebDir)) {
  throw "build\web wurde nicht gefunden. Bitte zuerst 'flutter build web --release --base-href /app/' ausfuehren."
}

if (Test-Path $hostingAppDir) {
  Get-ChildItem -LiteralPath $hostingAppDir -Force | Remove-Item -Recurse -Force
} else {
  New-Item -ItemType Directory -Path $hostingAppDir | Out-Null
}

Copy-Item -Path (Join-Path $buildWebDir "*") -Destination $hostingAppDir -Recurse -Force

$criticalFiles = @(
  "main.dart.js",
  "index.html",
  "flutter_bootstrap.js"
)

foreach ($file in $criticalFiles) {
  $sourceFile = Join-Path $buildWebDir $file
  $targetFile = Join-Path $hostingAppDir $file

  if (-not (Test-Path $sourceFile)) {
    throw "Kritische Build-Datei fehlt: $sourceFile"
  }

  Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force

  $sourceHash = (Get-FileHash -LiteralPath $sourceFile).Hash
  $targetHash = (Get-FileHash -LiteralPath $targetFile).Hash

  if ($sourceHash -ne $targetHash) {
    throw "Stage-Validierung fehlgeschlagen fuer $file. Build und Hosting sind nicht identisch."
  }
}

$mainJsFile = Join-Path $hostingAppDir "main.dart.js"
$bootstrapFile = Join-Path $hostingAppDir "flutter_bootstrap.js"
$mainJsVersion = ((Get-FileHash -LiteralPath $mainJsFile).Hash).Substring(0, 16).ToLowerInvariant()
$bootstrapContent = Get-Content -LiteralPath $bootstrapFile -Raw
$versionedMainJs = '"mainJsPath":"main.dart.js?v=' + $mainJsVersion + '"'
$updatedBootstrapContent = $bootstrapContent -replace '"mainJsPath":"main\.dart\.js"', $versionedMainJs

if ($updatedBootstrapContent -eq $bootstrapContent) {
  throw "Cache-Busting fuer main.dart.js konnte in flutter_bootstrap.js nicht gesetzt werden."
}

[System.IO.File]::WriteAllText(
  $bootstrapFile,
  $updatedBootstrapContent,
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Flutter-Web-Build wurde nach hosting/app staged."
