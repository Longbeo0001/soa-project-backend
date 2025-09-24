#!/bin/bash
# Script to generate .env file with AWS credentials, DB password, and DB URL based on environment (dev or prod)

# Default values
PROFILE_NAME="default"
OUTPUT_FILE=".env"
HELP=false
ENVIRONMENT=""
DB_PASSWORD="postgres"  # Default for dev
DB_URL="db"  # Default for dev

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to show help
show_help() {
    echo -e "${GREEN}AWS Credentials Converter${NC}"
    echo "=================================================="
    echo ""
    echo "Usage:"
    echo "  ./convert-aws-credentials.sh <environment> [-p <profile>] [-o <file>] [-h]"
    echo ""
    echo "Arguments:"
    echo "  <environment>    Environment to use (dev or prod)"
    echo ""
    echo "Options:"
    echo "  -p, --profile    AWS profile name (default: 'default', used in dev mode)"
    echo "  -o, --output     Output file name (default: '.env')"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./convert-aws-credentials.sh dev"
    echo "  ./convert-aws-credentials.sh prod"
    echo "  ./convert-aws-credentials.sh dev -p my-profile -o dev.env"
    echo ""
}

# Function to print colored output
print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_info() {
    echo -e "${CYAN}$1${NC}"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    print_error "Environment parameter (dev or prod) is required"
    show_help
    exit 1
fi

ENVIRONMENT="$1"
shift

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    print_error "Invalid environment: $ENVIRONMENT. Must be 'dev' or 'prod'"
    show_help
    exit 1
fi

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

echo -e "${GREEN}AWS Credentials Converter for $ENVIRONMENT${NC}"
echo "=============================="
echo ""

# Initialize credential variables
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_SESSION_TOKEN=""
AWS_REGION=""

# Function to fetch credentials for dev environment
fetch_dev_credentials() {
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
        grep -o '\[[^]]*\]' "$CREDENTIALS_PATH" | sed 's/\[//g' | sed 's/\]//g' | while read -r profile; do
            echo -e "  ${CYAN}- $profile${NC}"
        done
        exit 1
    fi

    print_success "Profile '$PROFILE_NAME' found"

    # Extract credentials for the specified profile
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile "$PROFILE_NAME" 2>/dev/null)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "$PROFILE_NAME" 2>/dev/null)
    AWS_REGION=$(aws configure get region --profile "$PROFILE_NAME" 2>/dev/null)

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_error "Failed to extract access key or secret key from profile"
        exit 1
    fi

    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="us-east-1"  # Default region
    fi
}

# Function to fetch credentials for prod environment (EC2 IMDSv2)
fetch_prod_credentials() {
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq not found. Please install jq to parse JSON."
        print_info "Installation guide: https://stedolan.github.io/jq/download/"
        exit 1
    fi

    # Obtain IMDSv2 token
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    if [ -z "$TOKEN" ]; then
        print_error "Failed to obtain IMDSv2 token. Ensure the script is running on an EC2 instance."
        exit 1
    fi

    # Retrieve credentials information from the instance's IAM Role
    ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
    if [ -z "$ROLE_NAME" ]; then
        print_error "Failed to retrieve IAM role name from IMDSv2."
        exit 1
    fi

    # Retrieve detailed credentials
    CREDS_JSON=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME)
    if [ -z "$CREDS_JSON" ]; then
        print_error "Failed to retrieve credentials from IMDSv2."
        exit 1
    fi

    # Extract credentials
    AWS_ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
    AWS_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.SessionToken')
    AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
        print_error "Failed to parse credentials from IMDSv2 response."
        exit 1
    fi

    if [ -z "$AWS_REGION" ]; then
        AWS_REGION="us-east-1"  # Default region
    fi

    # Fetch DB password and URL from Secrets Manager/Parameter Store for prod
    fetch_db_password
    fetch_db_url
}

# Function to fetch DB password from Secrets Manager for prod
fetch_db_password() {
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI first."
        print_info "Installation guide: https://aws.amazon.com/cli/"
        exit 1
    fi

    # Export credentials for AWS CLI in prod
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN
    export AWS_REGION

    # Fetch secret name from Parameter Store
    SECRET_NAME=$(aws ssm get-parameter --name "soa-param-codeland-db-secret-name" --query "Parameter.Value" --output text 2>/dev/null)
    if [ -z "$SECRET_NAME" ]; then
        print_error "Failed to retrieve secret name from Parameter Store."
        exit 1
    fi

    print_success "Secret name retrieved: $SECRET_NAME"

    # Fetch secret value from Secrets Manager
    SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --query "SecretString" --output text 2>/dev/null)
    if [ -z "$SECRET_VALUE" ]; then
        print_error "Failed to retrieve secret value from Secrets Manager."
        exit 1
    fi

    # Assume the secret is a JSON string with a 'password' key
    DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')
    if [ -z "$DB_PASSWORD" ]; then
        print_error "Failed to parse password from secret value."
        exit 1
    fi

    print_success "Database password retrieved successfully"
}

# Function to fetch DB URL from Parameter Store for prod
fetch_db_url() {
    # Fetch DB URL from Parameter Store
    DB_URL=$(aws ssm get-parameter --name "soa-param-codeland-db-url" --query "Parameter.Value" --output text 2>/dev/null)
    if [ -z "$DB_URL" ]; then
        print_error "Failed to retrieve DB URL from Parameter Store."
        exit 1
    fi

    print_success "Database URL retrieved: $DB_URL"
}

# Fetch credentials based on environment
if [ "$ENVIRONMENT" = "dev" ]; then
    fetch_dev_credentials
elif [ "$ENVIRONMENT" = "prod" ]; then
    fetch_prod_credentials
fi

print_success "Credentials extracted successfully"
echo -e "  ${CYAN}Access Key: ${AWS_ACCESS_KEY_ID:0:4}****${AWS_ACCESS_KEY_ID: -4}${NC}"
echo -e "  ${CYAN}Secret Key: ${AWS_SECRET_ACCESS_KEY:0:4}****${AWS_SECRET_ACCESS_KEY: -4}${NC}"
if [ -n "$AWS_SESSION_TOKEN" ]; then
    echo -e "  ${CYAN}Session Token: ${AWS_SESSION_TOKEN:0:4}****${AWS_SESSION_TOKEN: -4}${NC}"
fi
echo -e "  ${CYAN}Region: $AWS_REGION${NC}"

# Create environment variables content
cat > "$OUTPUT_FILE" << EOF
# Database Configuration
DB_USER=postgres
DB_PASSWORD=$DB_PASSWORD
DB_URL=$DB_URL
DB_PORT=5432
DB_NAME=dev

# Application Configuration
SECRET_KEY=my_precious
FLASK_APP=project/__init__.py
FLASK_DEBUG=1
APP_SETTINGS=project.config.DevelopmentConfig
PORT=80

# AWS S3 Configuration
STATIC_S3_BUCKET=soa-codeland-static
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_REGION=$AWS_REGION
EOF

# Add AWS_SESSION_TOKEN to .env file for prod environment
if [ "$ENVIRONMENT" = "prod" ] && [ -n "$AWS_SESSION_TOKEN" ]; then
    echo "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" >> "$OUTPUT_FILE"
fi

if [ $? -eq 0 ]; then
    print_success "Environment variables written to: $OUTPUT_FILE"
else
    print_error "Failed to write to file: $OUTPUT_FILE"
    exit 1
fi

# Display summary
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  Environment: $ENVIRONMENT"
echo "  Profile: $PROFILE_NAME (used in dev mode)"
echo "  Output File: $OUTPUT_FILE"
echo "  S3 Bucket: soa-codeland-static"
echo "  Region: $AWS_REGION"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the generated $OUTPUT_FILE file"
echo "2. Update STATIC_S3_BUCKET if needed"
echo "3. Run: docker-compose -f docker-compose-$ENVIRONMENT.yml up --build"
echo "4. Test: python backend/test_s3_config.py"
echo ""

echo -e "${GREEN}AWS credentials conversion completed!${NC}"

# Start the server
source ~/app/venv/bin/activate
echo "Starting Gunicorn server..."
cd ~/app/backend
exec gunicorn -b 0.0.0.0:$PORT manage:app \
  --workers 4 \
  --timeout 120 \
  --log-level info