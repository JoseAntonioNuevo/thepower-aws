# Guion de clase · Subir la API a AWS paso a paso

Actualizado el **12/11/2026** a partir del ensayo del profesor. Recorrido: **imagen Docker → ECR → configuración → ECS/Fargate → prueba real → limpieza**.

**Primera vez:** completa [Preparar AWS](preparar-aws.md). Ahí están todos los comandos para crear la red, permisos, secreto, registros y cluster que el profesor ya tenía preparados. Esta guía comienza con esa preparación terminada, sin servicio ni repositorio ECR.

Ejecuta desde la raíz del repositorio, en **Bash** (Mac/Linux) o **Git Bash** (Windows), en la misma terminal y en orden. Si falla un bloque, detente. No muestres `.env` ni la clave. En Windows sigue los requisitos de Python y Docker de la preparación. Una nueva terminal necesita volver a cargar el bloque 0.

## 0 · Recuperar tu configuración

**Carga los nombres guardados de tu proyecto y comprueba la identidad.**

```bash
source scripts/contexto.sh
set -o pipefail
s16_comprobar_identidad
```

Los nombres con `$` son datos que guardamos para usarlos después. Los archivos `.demo-aws/` contienen tus identificadores y quedan fuera de Git. En clase José usó `aws/contexto.sh`; en este repo público usamos `scripts/contexto.sh`, que carga **tus** datos. No necesitas ningún archivo privado del profesor.

Si caducó tu sesión, vuelve a entrar con el método que usaste en la preparación y repite este bloque.

## 1 · Construir las imágenes antes del directo

**Crea una imagen nativa para tu ordenador y otra compatible con el AWS de la demo.**

```bash
docker build -t s16-clasificador:local .
docker build --platform linux/amd64 -t s16-clasificador:1 .
docker image inspect s16-clasificador:1 --format '{{.Os}}/{{.Architecture}}'
```

La última debe mostrar `linux/amd64`, porque configuraremos Fargate como X86_64. La imagen local puede ser ARM64 en tu Mac; es correcto. Construye ambas de nuevo si cambias el código.

**Prueba en local el modo real siguiendo el [paso 2 del README](../README.md#2-probar-openrouter-en-local).** Debe responder con `modo: real`; detén el contenedor local al terminar. En clase estas imágenes ya estaban construidas y probadas.

## 2 · Mostrar de dónde partimos

**Muestra que todavía no hay aplicación funcionando ni acceso abierto.**

```bash
aws_demo ecs describe-clusters --clusters "$S16_CLUSTER" \
  --query 'clusters[].{tareas:runningTasksCount,pendientes:pendingTasksCount,servicios:activeServicesCount}'
aws_demo ec2 describe-security-groups --group-ids "$S16_SECURITY_GROUP" \
  --query 'SecurityGroups[0].IpPermissions'
```

Esperado: ceros y `[]`. En la web: región de tu proyecto → ECS, ECR, IAM, Secrets Manager (sin enseñar el valor) y Security groups.

`app.py` recibe un mensaje como «no puedo entrar en mi cuenta» y usa IA para devolver el tipo de problema, su prioridad y una respuesta sugerida. `Dockerfile` prepara el paquete; `.dockerignore` deja fuera la clave.

## 3 · Subir la imagen

**Crea en AWS el lugar donde guardaremos la imagen Docker.** La etiqueta `1` no podrá sobrescribirse.

```bash
aws_demo ecr create-repository --repository-name "$S16_REPOSITORY" \
  --image-tag-mutability IMMUTABLE \
  --encryption-configuration encryptionType=AES256 \
  --tags Key=Project,Value=thepower-s16 Key=Purpose,Value=classroom-demo
```

Si dice que ya existe, detente: comprueba si queda un ensayo por limpiar. No borres un repositorio ajeno ni intentes sobrescribir la etiqueta.

**Da permiso a Docker para subir imágenes a tu almacén de AWS.**

```bash
aws_demo ecr get-login-password \
  | docker login --username AWS --password-stdin "$S16_REGISTRY"
```

**Pon a la imagen la dirección de destino que tendrá en AWS.**

```bash
docker tag s16-clasificador:1 "$S16_IMAGE"
```

**Sube la imagen desde tu ordenador a AWS.**

```bash
docker push "$S16_IMAGE"
```

**Comprueba que AWS tiene la etiqueta y la huella de esa imagen.**

```bash
aws_demo ecr describe-images --repository-name "$S16_REPOSITORY" \
  --image-ids imageTag=1 --query 'imageDetails[].{etiqueta:imageTags,huella:imageDigest}'
```

En la web: ECR → tu repositorio → Images → etiqueta `1`.

## 4 · Guardar cómo se ejecutará

**Genera la configuración con tu imagen, red, recursos y referencia a la clave.**

```bash
python3 scripts/preparar-json.py
```

Puedes abrir `.demo-aws/task-definition.json`: no contiene la clave, solo dónde encontrarla. Son los mismos parámetros del ensayo: Linux X86_64, 0,25 vCPU, 512 MiB, puerto 8000, OpenRouter real, Luna y proveedor rápido. Usamos una subred propia; el profesor tenía tres subredes preparadas, pero una basta para esta demo.

**Guarda la configuración en AWS y conserva su identificador.**

```bash
S16_TASK_DEF_ARN="$(aws_demo ecs register-task-definition \
  --cli-input-json file://.demo-aws/task-definition.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
printf '%s\n' "$S16_TASK_DEF_ARN"
```

**Abre el puerto 8000 solo para tu conexión actual y poder probar la API.**

```bash
bash scripts/actualizar-ip.sh --execute
```

Si cambias de red o VPN después, repite este último comando: sustituye la IP anterior, sin acumular accesos.

## 5 · Arrancar la aplicación

**Busca la configuración del paso anterior para que no falle por haber perdido la variable en la terminal.**

```bash
S16_TASK_DEF_ARN="$(aws_demo ecs describe-task-definition \
  --task-definition "$S16_SERVICE" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
printf '%s\n' "$S16_TASK_DEF_ARN"
```

Debe imprimir un identificador que empieza por `arn:aws:ecs:`; si aparece vacío o `None`, detente y revisa el paso 4.

**Arranca una copia con la imagen, recursos, clave y red preparados.**

```bash
aws_demo ecs create-service \
  --cluster "$S16_CLUSTER" --service-name "$S16_SERVICE" \
  --task-definition "${S16_TASK_DEF_ARN:?Falta recuperar la definicion de tarea}" --desired-count 1 \
  --launch-type FARGATE --platform-version 1.4.0 \
  --network-configuration file://.demo-aws/network.json \
  --deployment-configuration 'minimumHealthyPercent=0,maximumPercent=100,deploymentCircuitBreaker={enable=true,rollback=true}' \
  --tags key=Project,value=thepower-s16 key=Purpose,value=classroom-demo \
  --query 'service.{nombre:serviceName,deseadas:desiredCount,estado:status}'
```

`1` pide una copia; Fargate aporta CPU y memoria sin preparar un servidor. El servicio vuelve a arrancarla si se para. Si el despliegue falla, AWS detiene el intento; puede volver al anterior si había uno correcto.

**Espera a que AWS termine de arrancarla; puede tardar varios minutos.**

```bash
aws_demo ecs wait services-stable --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
```

**Confirma que hay una copia funcionando.**

```bash
aws_demo ecs describe-services --cluster "$S16_CLUSTER" --services "$S16_SERVICE" \
  --query 'services[].{deseadas:desiredCount,ejecutandose:runningCount,pendientes:pendingCount,eventos:events[:3].message}'
```

Esperado: `1`, `1`, `0`. Si falla la espera, revisa esos eventos y los registros del paso 6; no crees servicios duplicados. En la web: ECS → tu cluster → Tasks.

## 6 · Probar el resultado

**Busca la dirección nueva de la aplicación y muestra el enlace para abrirla.**

```bash
S16_PUBLIC_IP="$(bash scripts/ip-publica.sh)"
printf 'http://%s:8000/docs\n' "${S16_PUBLIC_IP:?No se pudo obtener la direccion}"
```

**Comprueba que responde; debe devolver `ok` y `real`.**

```bash
curl --fail-with-body --connect-timeout 5 --max-time 10 \
  "http://${S16_PUBLIC_IP:?Falta la direccion}:8000/health"
```

**Envía el mensaje a la IA y muestra el tipo de problema, su prioridad y una respuesta sugerida.**

```bash
curl --fail-with-body --connect-timeout 5 --max-time 40 \
  "http://${S16_PUBLIC_IP:?Falta la direccion}:8000/clasificar" \
  -H 'Content-Type: application/json' \
  -d '{"texto":"No puedo entrar en mi cuenta ficticia"}'
```

La respuesta debe indicar `modo: real` y `modelo: openai/gpt-6-luna`; normalmente la categoría será `acceso`. El texto puede variar. `/health` no llama al modelo; `/clasificar` sí genera consumo. Un `502` o `503` no es una clasificación correcta.

**Muestra los mensajes de arranque guardados en AWS.**

```bash
aws_demo logs tail "$S16_LOG_GROUP" --since 30m
```

Opcional: abre `/docs` en el navegador para mostrar el resultado visualmente. Esta prueba usa HTTP temporal restringido a tu IP, solo con datos ficticios; no es el acceso de una API de producción.

## 7 · Terminar y limpiar lo desplegado

**Comprueba de nuevo el proyecto antes de borrar los recursos de esta demo.**

```bash
s16_comprobar_identidad
```

**Pide cero copias para parar la API y evitar que vuelva a arrancar.**

```bash
aws_demo ecs update-service --cluster "$S16_CLUSTER" --service "$S16_SERVICE" \
  --desired-count 0 --query 'service.desiredCount'
```

**Espera a que termine de pararse.**

```bash
aws_demo ecs wait services-stable --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
```

**Elimina el servicio que mantenía la aplicación funcionando y espera a su retirada.**

```bash
aws_demo ecs delete-service --cluster "$S16_CLUSTER" --service "$S16_SERVICE" --query 'service.status'
aws_demo ecs wait services-inactive --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
```

**Borra el repositorio de esta práctica con todas sus imágenes y manifiestos; la imagen local se conserva.**

```bash
aws_demo ecr delete-repository --repository-name "$S16_REPOSITORY" --force
```

**Busca la regla del puerto 8000 y elimínala si sigue existiendo.**

```bash
S16_RULE_ID="$(aws_demo ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$S16_SECURITY_GROUP" \
  --query 'SecurityGroupRules[?IsEgress==`false` && IpProtocol==`tcp` && FromPort==`8000` && ToPort==`8000`].SecurityGroupRuleId | [0]' \
  --output text)"
if [ -n "$S16_RULE_ID" ] && [ "$S16_RULE_ID" != "None" ]; then
  aws_demo ec2 revoke-security-group-ingress --group-id "$S16_SECURITY_GROUP" \
    --security-group-rule-ids "$S16_RULE_ID"
fi
```

Así no dependes de recordar el identificador de la regla ni falla si ya estaba retirada.

## 8 · Comprobar la limpieza y repetir

**Comprueba que no quedan tareas, servicios activos, entradas abiertas ni conexiones de la tarea.**

```bash
aws_demo ecs describe-clusters --clusters "$S16_CLUSTER" \
  --query 'clusters[].{tareas:runningTasksCount,pendientes:pendingTasksCount,servicios:activeServicesCount}'
aws_demo ec2 describe-security-groups --group-ids "$S16_SECURITY_GROUP" --query 'SecurityGroups[0].IpPermissions'
aws_demo ec2 describe-network-interfaces --filters "Name=group-id,Values=$S16_SECURITY_GROUP" \
  --query 'NetworkInterfaces[].{id:NetworkInterfaceId,estado:Status}'
```

Esperado: ceros y dos `[]`. Las conexiones de red pueden tardar un poco en desaparecer; vuelve a comprobarlas si aparecen. ECR debe mostrar que el repositorio ya no existe.

Conservamos red, cluster, rol, secreto, logs y la configuración de tarea, como en el ensayo del profesor. No ejecutan la API; el secreto y los registros pueden seguir generando coste. Para repetir, vuelve al paso 0 y después al 2 si las imágenes y el código siguen iguales. Si no vas a repetir, usa [Limpieza completa](limpieza-completa.md).
