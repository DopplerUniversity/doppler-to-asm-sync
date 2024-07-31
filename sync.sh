#!/usr/bin/env bash

function handler () {
  EVENT_DATA=$1
  EVENT_JSON=$(echo "$EVENT_DATA" | jq -r '.body' | jq -c)

  webhook_project=$(echo "$EVENT_JSON" | jq -r '.project.name')
  webhook_config=$(echo "$EVENT_JSON" | jq -r '.config.name')
  webhook=$(echo "$EVENT_JSON" | jq -r '"\(.webhook.name).\(.webhook.id)"')

  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "jq could not be found, please install jq to process JSON data."
    exit 1
  fi

  # Check if aws is installed
  if ! command -v aws &> /dev/null; then
    echo "aws could not be found, please install the aws CLI."
    exit 1
  fi

  # Check if doppler is installed
  if ! command -v doppler &> /dev/null; then
    echo "doppler could not be found, please install the doppler CLI."
    exit 1
  fi

  # A DOPPLER_TOKEN is always required in some form
  if [ -z "${DOPPLER_TOKEN+x}" ]; then
    echo "DOPPLER_TOKEN not specified"
    exit 1
  fi

  # DOPPLER_PROJECT and DOPPLER_CONFIG are only required if the token isn't a
  # service token, which can be determined by the prefix. If it's a Service Token
  # then the project and config are hard-coded to the token.
  if [ "${DOPPLER_TOKEN:0:6}" != "dp.st." ]; then
    # check the webhook payload to see if it contains the project and config name
    if [ -z "${DOPPLER_PROJECT+x}" ] && [ "$webhook_project" != "null" ]; then
      DOPPLER_PROJECT=$webhook_project
    fi
    if [ -z "${DOPPLER_CONFIG+x}" ] && [ "$webhook_config" != "null" ]; then
      DOPPLER_CONFIG=$webhook_config
    fi

    if [ -z "${DOPPLER_PROJECT+x}" ]; then
      echo "DOPPLER_PROJECT not specified"
      exit 1
    fi

    if [ -z "${DOPPLER_CONFIG+x}" ]; then
      echo "DOPPLER_CONFIG not specified"
      exit 1
    fi
  fi

  # Fetch secrets from Doppler as JSON
  secrets_json=""
  if [ -z "${DOPPLER_PROJECT+x}" ]; then 
    secrets_json=$(doppler secrets download --no-file)
  else
    secrets_json=$(doppler secrets download --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" --no-file)
  fi

  if [ -z "${AWS_SECRET_ARN+x}" ]; then
    # if AWS_SECRET_ARN isn't set for the lambda, then look for it in the Doppler
    # secrets. this allows for dynamically specifying which secret to update based
    # on the config that was updated as specified by the webhook payload.
    AWS_SECRET_ARN=$(echo "$secrets_json" | jq -r '.AWS_SECRET_ARN')
    if [ "$AWS_SECRET_ARN" = "null" ]; then
      echo "AWS_SECRET_ARN not specified"
      exit 1
    fi
  fi

  # Convert secret names to lowercase and replaces `_` with `-`. You can replace
  # any character with another here as desired. If multiple characters need to be
  # replaced use a regular expression like `gsub("[_:]";"-")`
  transformed_secrets_json=$(echo "$secrets_json" | jq -c 'del(.AWS_SECRET_ARN, .DOPPLER_PROJECT, .DOPPLER_CONFIG, .DOPPLER_ENVIRONMENT) | with_entries(.key |= (ascii_downcase | gsub("_";"-")))')

  # Update the secret value in AWS Secrets Manager
  aws secretsmanager put-secret-value --secret-id "$AWS_SECRET_ARN" --secret-string "$transformed_secrets_json" > /dev/null

  RESPONSE="{\"statusCode\": 200, \"body\": \"{ \"message\": \"Secrets updated\", \"doppler_project\": \"${DOPPLER_PROJECT:-$webhook_project}\", \"doppler_config\": \"${DOPPLER_CONFIG:-$webhook_config}\", \"doppler_webhook\": \"$webhook\", \"aws_secret_arn\": \"${AWS_SECRET_ARN}\" }\"}"
  echo $RESPONSE
}