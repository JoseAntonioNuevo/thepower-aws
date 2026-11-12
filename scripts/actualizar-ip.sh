#!/usr/bin/env bash
# Ejecutar antes de clase, desde la conexión que hará las peticiones HTTP.
set -euo pipefail
if [[ ${1:-} != --execute ]]; then
    echo 'Uso: bash aws/actualizar-ip.sh --execute' >&2
    exit 2
fi
source "$(dirname "$0")/contexto.sh"
s16_comprobar_identidad

# No confiamos en que una VPN o la red del aula mantenga la IP anterior.
s16_ip="$(curl -4fsS --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com)"
python3 - "$s16_ip" <<'PY'
import ipaddress
import sys

address = ipaddress.IPv4Address(sys.argv[1])
if not address.is_global:
    raise SystemExit('STOP: se requiere una IPv4 pública válida')
PY

# Verificar identidad y etiquetas antes de modificar este grupo propio.
s16_group="$(aws_demo ec2 describe-security-groups --group-ids "$S16_SECURITY_GROUP" --output json)"
python3 - "$s16_group" <<'PY'
import json
import sys

group = json.loads(sys.argv[1])['SecurityGroups'][0]
tags = {tag['Key']: tag['Value'] for tag in group.get('Tags', [])}
assert group['OwnerId'] == __import__('os').environ['S16_PROJECT_ID']
assert group['VpcId'] == __import__('os').environ['S16_VPC']
assert group['GroupName'] == __import__('os').environ['S16_SERVICE']
assert tags.get('Project') == 'thepower-s16'
assert tags.get('ManagedBy') == 'thepower-student'
PY

s16_rules="$(aws_demo ec2 describe-security-group-rules --filters "Name=group-id,Values=$S16_SECURITY_GROUP" --output json)"
s16_rule_id="$(python3 - "$s16_rules" <<'PY'
import json
import sys

ingress = [r for r in json.loads(sys.argv[1])['SecurityGroupRules'] if not r['IsEgress']]
if len(ingress) > 1:
    raise SystemExit('STOP: varias entradas; revisar el grupo antes de modificarlo')
if ingress:
    rule = ingress[0]
    if (rule['IpProtocol'], rule.get('FromPort'), rule.get('ToPort')) != ('tcp', 8000, 8000):
        raise SystemExit('STOP: regla ajena al puerto de la demo')
    if 'CidrIpv4' not in rule or not rule['CidrIpv4'].endswith('/32'):
        raise SystemExit('STOP: la entrada existente no es una IPv4 /32')
    print(rule['SecurityGroupRuleId'])
PY
)"

if [[ -n $s16_rule_id ]]; then
    # Sustituye la IP anterior: no acumula accesos de redes antiguas.
    aws_demo ec2 modify-security-group-rules --group-id "$S16_SECURITY_GROUP" \
        --security-group-rules "SecurityGroupRuleId=$s16_rule_id,SecurityGroupRule={IpProtocol=tcp,FromPort=8000,ToPort=8000,CidrIpv4=$s16_ip/32,Description=IP actual del alumno S16}"
else
    aws_demo ec2 authorize-security-group-ingress --group-id "$S16_SECURITY_GROUP" \
        --protocol tcp --port 8000 --cidr "$s16_ip/32" \
        --query 'SecurityGroupRules[].SecurityGroupRuleId' --output text
fi
aws_demo ec2 describe-security-groups --group-ids "$S16_SECURITY_GROUP" \
    --query 'SecurityGroups[0].IpPermissions'
echo 'Entrada preparada: TCP 8000 solo desde la IPv4 actual /32.'
