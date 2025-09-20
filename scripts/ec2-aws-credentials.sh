#!/bin/bash
# Script to retrieve AWS credentials from IMDSv2 and set environment variables

# Obtain IMDSv2 token (required for IMDSv2)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Retrieve credentials information from the instance's IAM Role
CREDENTIALS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)

# Extract role name (assuming the instance has only one role)
ROLE_NAME=$(echo $CREDENTIALS | jq -r '.')

# Retrieve detailed credentials (AccessKeyId, SecretAccessKey, Token)
CREDS_JSON=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME)

# Extract AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN
AWS_ACCESS_KEY_ID=$(echo $CREDS_JSON | jq -r '.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo $CREDS_JSON | jq -r '.SecretAccessKey')
AWS_SESSION_TOKEN=$(echo $CREDS_JSON | jq -r '.SessionToken')

# Set values as environment variables
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
