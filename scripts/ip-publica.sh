#!/usr/bin/env bash
# Solo consulta AWS: muestra la dirección de la aplicación sin crear recursos.
set -euo pipefail
source "$(dirname "$0")/contexto.sh"
s16_comprobar_identidad >/dev/null

s16_task="$(aws_demo ecs list-tasks \
  --cluster "$S16_CLUSTER" --service-name "$S16_SERVICE" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)"
if [[ -z $s16_task || $s16_task == None ]]; then
    echo 'La aplicación todavía no está ejecutándose. Revisa ECS → Tasks.' >&2
    exit 1
fi

# Cada ejecución tiene una conexión de red; buscamos su dirección pública.
s16_eni="$(aws_demo ecs describe-tasks --cluster "$S16_CLUSTER" --tasks "$s16_task" \
  --query 'tasks[0].attachments[].details[?name==`networkInterfaceId`].value[] | [0]' \
  --output text)"
if [[ -z $s16_eni || $s16_eni == None ]]; then
    echo 'La conexión de red aún no está disponible. Revisa la tarea.' >&2
    exit 1
fi
s16_public_ip="$(aws_demo ec2 describe-network-interfaces --network-interface-ids "$s16_eni" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"

# Si AWS no devuelve una dirección válida, no continuar con una URL incorrecta.
python3 - "$s16_public_ip" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.IPv4Address(sys.argv[1])
    if not address.is_global:
        raise ValueError
except ValueError:
    raise SystemExit('No hay IP pública válida. Revisa Public IP de la tarea.') from None
print(address)
PY
