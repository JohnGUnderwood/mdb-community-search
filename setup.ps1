#!/usr/bin/env pwsh
# MongoDB Community Search - Setup Script for Windows

Write-Host "MongoDB Community Search - Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Generate keyfile if it doesn't exist
if (-not (Test-Path "keyfile")) {
    Write-Host "Generating keyfile..." -ForegroundColor Yellow
    
    # Generate 756 bytes of random data and base64 encode it
    $bytes = New-Object byte[] 567
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $base64 = [Convert]::ToBase64String($bytes)
    
    # Write to file without BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PWD\keyfile", $base64, $utf8NoBom)
    
    Write-Host "Keyfile generated successfully" -ForegroundColor Green
} else {
    Write-Host "Keyfile already exists" -ForegroundColor Green
}

# Create password file
$MONGOT_PASSWORD = if ($env:MONGOT_PASSWORD) { $env:MONGOT_PASSWORD } else { "mongotPassword" }
Write-Host "Creating password file..." -ForegroundColor Yellow
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\passwordFile", $MONGOT_PASSWORD, $utf8NoBom)
Write-Host "Password file created successfully" -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete! You can now run:" -ForegroundColor Green
Write-Host ""
Write-Host "Option 1 - Run MongoDB and Search only:" -ForegroundColor Yellow
Write-Host "  docker-compose up mongod mongot -d"
Write-Host ""
Write-Host "Option 2 - Run full stack (includes Prometheus and Grafana):" -ForegroundColor Yellow
Write-Host "  docker-compose up -d"
