#!/usr/bin/env bash
# Solo guarda identificadores de esta práctica: nunca claves ni tokens.
set -euo pipefail
mkdir -p .demo-aws
umask 077
s16_tmp="$(mktemp .demo-aws/contexto.XXXXXX)"
for s16_name in AWS_PROFILE AWS_REGION S16_PROJECT_ID S16_NAME S16_CLUSTER S16_SERVICE S16_REPOSITORY S16_REGISTRY S16_IMAGE S16_EXECUTION_ROLE S16_SECRET_NAME S16_SECRET_ARN S16_LOG_GROUP S16_VPC S16_SUBNET S16_IGW S16_ROUTE_TABLE S16_ROUTE_ASSOC S16_SECURITY_GROUP; do
    if [[ -n ${!s16_name:-} ]]; then
        printf 'export %s=%q\n' "$s16_name" "${!s16_name}" >> "$s16_tmp"
    fi
done
mv "$s16_tmp" .demo-aws/contexto.sh
