# Convert AWS Credentials to Environment Variables
# PowerShell Script for Windows

param(
    [string]$ProfileName = "default",
    [string]$OutputFile = ".env",
    [switch]$Help
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Cyan = "Cyan"

# Function to show help
function Show-Help {
    Write-Host "AWS Credentials Converter for Profile Image Feature" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\convert-aws-credentials.ps1 [-ProfileName <profile>] [-OutputFile <file>] [-Help]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -ProfileName    AWS profile name (default: 'default')"
    Write-Host "  -OutputFile     Output file name (default: '.env')"
    Write-Host "  -Help           Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\convert-aws-credentials.ps1"
    Write-Host "  .\convert-aws-credentials.ps1 -ProfileName my-profile"
    Write-Host "  .\convert-aws-credentials.ps1 -OutputFile production.env"
    Write-Host ""
}

# Function to print colored output
function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

# Show help if requested
if ($Help) {
    Show-Help
    exit 0
}

Write-Host "AWS Credentials Converter" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Write-Host ""

# Check if AWS CLI is installed
$awsCommand = Get-Command aws -ErrorAction SilentlyContinue
if (-not $awsCommand) {
    Write-Error "AWS CLI not found. Please install AWS CLI first."
    Write-Info "Installation guide: https://aws.amazon.com/cli/"
    exit 1
}

try {
    $awsVersion = & aws --version 2>$null
    Write-Success "AWS CLI found: $awsVersion"
} catch {
    Write-Error "Failed to get AWS CLI version"
    exit 1
}

# Check if credentials file exists
$credentialsPath = "$env:USERPROFILE\.aws\credentials"
if (-not (Test-Path $credentialsPath)) {
    Write-Error "AWS credentials file not found at: $credentialsPath"
    Write-Warning "Please run 'aws configure' first to set up your credentials."
    exit 1
}

Write-Success "AWS credentials file found"

# Check if profile exists in credentials
$credentialsContent = Get-Content $credentialsPath -Raw
if (-not ($credentialsContent -match "\[$ProfileName\]")) {
    Write-Error "Profile '$ProfileName' not found in credentials file"
    Write-Info "Available profiles:"
    
    # Extract all profile names
    $profiles = [regex]::Matches($credentialsContent, '\[([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value }
    foreach ($profile in $profiles) {
        Write-Host "  - $profile" -ForegroundColor Cyan
    }
    exit 1
}

Write-Success "Profile '$ProfileName' found"

# Extract credentials for the specified profile
try {
    $accessKey = & aws configure get aws_access_key_id --profile $ProfileName 2>$null
    $secretKey = & aws configure get aws_secret_access_key --profile $ProfileName 2>$null
    
    if ([string]::IsNullOrEmpty($accessKey) -or [string]::IsNullOrEmpty($secretKey)) {
        Write-Error "Failed to extract access key or secret key from profile"
        exit 1
    }
} catch {
    Write-Error "Failed to extract credentials from AWS CLI"
    exit 1
}

# Get region
try {
    $region = & aws configure get region --profile $ProfileName 2>$null
    if ([string]::IsNullOrEmpty($region)) {
        $region = "us-east-1"  # Default region
    }
} catch {
    $region = "us-east-1"  # Default region
}

Write-Success "Credentials extracted successfully"
$accessKeyMasked = $accessKey.Substring(0, 4) + "****" + $accessKey.Substring($accessKey.Length - 4)
$secretKeyMasked = $secretKey.Substring(0, 4) + "****" + $secretKey.Substring($secretKey.Length - 4)
Write-Host "  Access Key: $accessKeyMasked" -ForegroundColor Cyan
Write-Host "  Secret Key: $secretKeyMasked" -ForegroundColor Cyan
Write-Host "  Region: $region" -ForegroundColor Cyan

# Create environment variables content
$envContent = @"
# Database Configuration
DB_USER=postgres
DB_PASSWORD=postgres
DB_URL=db
DB_PORT=5432
DB_NAME=dev

# Application Configuration
SECRET_KEY=my_precious
FLASK_APP=project/__init__.py
FLASK_DEBUG=1
APP_SETTINGS=project.config.DevelopmentConfig
PORT=80

# AWS S3 Configuration for Profile Images
STATIC_S3_BUCKET=soa-codeland-static
AWS_ACCESS_KEY_ID=$accessKey
AWS_SECRET_ACCESS_KEY=$secretKey
AWS_REGION=$region

# Logging Configuration
LOG_LEVEL=INFO
LOG_TO_STDOUT=false
"@

try {
    $envContent | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Success "Environment variables written to: $OutputFile"
} catch {
    Write-Error "Failed to write to file: $OutputFile"
    Write-Error $_.Exception.Message
    exit 1
}

# Display summary
Write-Host ""
Write-Host "Summary:" -ForegroundColor Green
Write-Host "  Profile: $ProfileName"
Write-Host "  Output File: $OutputFile"
Write-Host "  S3 Bucket: soa-codeland-static"
Write-Host "  Region: $region"
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Review the generated $OutputFile file"
Write-Host "2. Update STATIC_S3_BUCKET if needed"
Write-Host "3. Run: docker-compose -f docker-compose-dev.yml up --build"
Write-Host "4. Test: python backend/test_s3_config.py"
Write-Host ""

Write-Host "🎉 AWS credentials conversion completed!" -ForegroundColor Green