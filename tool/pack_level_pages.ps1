# Упаковка build/level_pages/<имя>/ в docs/levels/<имя>.docx.
# Запуск после: flutter test tool/generate_level_pages_test.dart
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path $PSScriptRoot -Parent
$staging = Join-Path $root 'build\level_pages'
$out = Join-Path $root 'docs\levels'
New-Item -ItemType Directory -Force $out | Out-Null

Get-ChildItem $staging -Directory | ForEach-Object {
    $dest = Join-Path $out "$($_.Name).docx"
    try {
        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction Stop }
        $fs = [System.IO.File]::Open($dest, 'Create')
        $zip = New-Object System.IO.Compression.ZipArchive($fs, 'Create')
        foreach ($rel in @('[Content_Types].xml', '_rels/.rels', 'word/document.xml')) {
            $entry = $zip.CreateEntry($rel)
            $es = $entry.Open()
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $_.FullName ($rel -replace '/', '\')))
            $es.Write($bytes, 0, $bytes.Length)
            $es.Close()
        }
        $zip.Dispose()
        $fs.Close()
        Write-Output "OK: $($_.Name).docx"
    } catch {
        Write-Output "FAIL: $($_.Name).docx -> $($_.Exception.Message)"
    }
}
