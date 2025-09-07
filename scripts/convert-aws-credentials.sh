#!/bin/bash

# Convert AWS Credentials to Environment Variables
# Shell Script for Linux/macOS

# Default values
PROFILE_NAME="default"
OUTPUT_FILE=".env"
HELP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show help
show_help() {
    echo -e "${GREEN}AWS Credentials Converter for Profile Image Feature${NC}"
    echo "=================================================="
    echo ""
    echo "Usage:"
    echo "  ./convert-aws-credentials.sh [-p <profile>] [-o <file>] [-h]"
    echo ""
    echo "Options:"
    echo "  -p, --profile    AWS profile name (default: 'default')"
    echo "  -o, --output     Output file name (default: '.env')"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./convert-aws-credentials.sh"
    echo "  ./convert-aws-credentials.sh -p my-profile"
    echo "  ./convert-aws-credentials.sh -o production.env"
    echo ""
}

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--profile)
            PROFILE_NAME="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$HELP" = true ]; then
    show_help
    exit 0
fi

echo -e "${GREEN}AWS Credentials Converter${NC}"
echo "=============================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install AWS CLI first."
    print_info "Installation guide: https://aws.amazon.com/cli/"
    exit 1
fi

AWS_VERSION=$(aws --version 2>/dev/null)
print_success "AWS CLI found: $AWS_VERSION"

# Check if credentials file exists
CREDENTIALS_PATH="$HOME/.aws/credentials"
if [ ! -f "$CREDENTIALS_PATH" ]; then
    print_error "AWS credentials file not found at: $CREDENTIALS_PATH"
    print_warning "Please run 'aws configure' first to set up your credentials."
    exit 1
fi

print_success "AWS credentials file found"

# Check if profile exists in credentials
if ! grep -q "\[$PROFILE_NAME\]" "$CREDENTIALS_PATH"; then
    print_error "Profile '$PROFILE_NAME' not found in credentials file"
    print_info "Available profiles:"
    
    # Extract all profile names
    grep -o '\[[^]]*\]' "$CREDENTIALS_PATH" | sed 's/\[//g' | sed 's/\]//g' | while read -r profile; do
        echo -e "  ${CYAN}- $profile${NC}"
    done
    exit 1
fi

print_success "Profile '$PROFILE_NAME' found"

# Extract credentials for the specified profile
ACCESS_KEY=$(aws configure get aws_access_key_id --profile "$PROFILE_NAME" 2>/dev/null)
SECRET_KEY=$(aws configure get aws_secret_access_key --profile "$PROFILE_NAME" 2>/dev/null)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    print_error "Failed to extract access key or secret key from profile"
    exit 1
fi

# Get region
REGION=$(aws configure get region --profile "$PROFILE_NAME" 2>/dev/null)
if [ -z "$REGION" ]; then
    REGION="us-east-1"  # Default region
fi

print_success "Credentials extracted successfully"
echo -e "  ${CYAN}Access Key: ${ACCESS_KEY:0:4}****${ACCESS_KEY: -4}${NC}"
echo -e "  ${CYAN}Secret Key: ${SECRET_KEY:0:4}****${SECRET_KEY: -4}${NC}"
echo -e "  ${CYAN}Region: $REGION${NC}"

# Create environment variables content
cat > "$OUTPUT_FILE" << EOF
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
AWS_ACCESS_KEY_ID=$ACCESS_KEY
AWS_SECRET_ACCESS_KEY=$SECRET_KEY
AWS_REGION=$REGION

# Logging Configuration
LOG_LEVEL=INFO
LOG_TO_STDOUT=false
EOF

if [ $? -eq 0 ]; then
    print_success "Environment variables written to: $OUTPUT_FILE"
else
    print_error "Failed to write to file: $OUTPUT_FILE"
    exit 1
fi

# Display summary
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  Profile: $PROFILE_NAME"
echo "  Output File: $OUTPUT_FILE"
echo "  S3 Bucket: soa-codeland-static"
echo "  Region: $REGION"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the generated $OUTPUT_FILE file"
echo "2. Update STATIC_S3_BUCKET if needed"
echo "3. Run: docker-compose -f docker-compose-dev.yml up --build"
echo "4. Test: python backend/test_s3_config.py"
echo ""

echo -e "${GREEN}🎉 AWS credentials conversion completed!${NC}"
