#!/bin/sh
# https://stackoverflow.com/a/38732187/1935918
set -e

# usage: file_env VAR
#    ie: file_env 'XYZ_DB_PASSWORD'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
  local var="$1"
  local fileVar="${var}_FILE"

  # The variables are already defined from the docker-light-baseimage
  # So if the _FILE variable is available we ovewrite them
  if [ "${!fileVar:-}" ]; then
    echo "${fileVar} was defined"
    val="$(< "${!fileVar}")"
    echo "${var} was replaced with the contents of ${fileVar} (the value was: ${val})"
    export "$var"="$val"
  fi

  unset "$fileVar"
}

file_env 'API_CPS_CLIENT_ID'
file_env 'API_CPS_CLIENT_SECRET'
file_env 'API_CPS_PASSWORD'
file_env 'API_CPS_USERNAME'
file_env 'API_ISPF_PASSWORD'
file_env 'API_ISPF_USER'
file_env 'CRISP_CLIENT_KEY'
file_env 'DB_PASSWORD'
file_env 'DB_PASSWORD'
file_env 'DB_USERNAME'
file_env 'DB_USERNAME'
file_env 'FC_PARTICULIER_ID'
file_env 'FC_PARTICULIER_SECRET'
file_env 'GITHUB_CLIENT_ID'
file_env 'GITHUB_CLIENT_SECRET'
file_env 'GOOGLE_CLIENT_ID'
file_env 'GOOGLE_CLIENT_SECRET'
file_env 'HELPSCOUT_CLIENT_ID'
file_env 'HELPSCOUT_CLIENT_SECRET'
file_env 'HELPSCOUT_WEBHOOK_SECRET'
file_env 'MICROSOFT_CLIENT_ID'
file_env 'MICROSOFT_CLIENT_SECRET'
file_env 'OTP_SECRET_KEY'
file_env 'S3_ACCESS_KEY'
file_env 'S3_ACCESS_KEY'
file_env 'S3_SECRET_KEY'
file_env 'S3_SECRET_KEY'
file_env 'SENTRY_DSN_JS'
file_env 'SENTRY_DSN_JS'
file_env 'SENTRY_DSN_RAILS'
file_env 'SENTRY_DSN_RAILS'
file_env 'TATOU_CLIENT_ID'
file_env 'TATOU_CLIENT_SECRET'
file_env 'UNIVERSIGN_USERPWD'
file_env 'YAHOO_CLIENT_ID'
file_env 'YAHOO_CLIENT_SECRET'

if [ -f /app/tmp/pids/server.pid ]; then
  rm /app/tmp/pids/server.pid
fi

bundle exec rake db:migrate || bundle exec rake db:setup
bundle exec rake after_party:run || true
bundle exec rake jobs:schedule

exec bundle exec "$@"
