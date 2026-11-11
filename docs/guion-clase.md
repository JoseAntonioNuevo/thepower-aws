# Guion de la demo · Docker, AWS y OpenRouter

Ejecuta los bloques desde la raíz del repositorio, en Bash/Zsh o Git Bash en Windows; detente si falla uno. Docker y AWS CLI deben estar instalados, y `.env` configurado según el [README](../README.md).

Para la parte AWS, prepara primero un cluster Fargate, un rol de ejecución con acceso a ECR/logs y a tu secreto, un grupo de logs y un grupo de seguridad **propio y sin entradas**, siguiendo los pasos 4 y 5 del README. Usa subredes públicas con ruta a Internet. Los valores de abajo son tuyos: no uses los del profesor. Esta demo genera consumo temporal e inferencia; HTTP restringido es solo para datos ficticios.

Configurar el perfil, región e identificadores propios de la infraestructura preparada.

```bash
export AWS_PROFILE=tu-perfil
export AWS_REGION=eu-north-1
export AWS_PAGER=''
S16_CLUSTER=tu-cluster
S16_EXECUTION_ROLE_ARN=arn-de-tu-rol-de-ejecucion
S16_SECRET_ARN=arn-de-tu-secreto-openrouter
S16_LOG_GROUP=/s16/tu-nombre
S16_SUBNET=subnet-de-tu-red-publica
S16_SECURITY_GROUP=sg-de-tu-grupo-propio
S16_REPOSITORY=s16-clasificador
S16_SERVICE=s16-clasificador
aws_demo() { command aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"; }
aws_demo sts get-caller-identity
```

Verifica que la identidad sea la de tu proyecto y que la región sea la asignada a él; Estocolmo es solo el ejemplo de la clase.

Construir la imagen nativa para tu equipo y la imagen AMD64 para Fargate X86_64.

```bash
docker build -t s16-clasificador:local .
docker build --platform linux/amd64 -t s16-clasificador:1 .
```

Arrancar la API local con sus variables, sin incorporar la clave a la imagen.

```bash
docker run --rm -d --name s16-demo --env-file .env -p 127.0.0.1:8000:8000 s16-clasificador:local
```

Comprobar salud y clasificación real, después de unos segundos de arranque.

```bash
curl --fail-with-body http://127.0.0.1:8000/health
curl --fail-with-body --max-time 40 http://127.0.0.1:8000/clasificar \
  -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta ficticia"}'
docker stop s16-demo
```

Crear un repositorio ECR exclusivo de esta práctica y guardar la URI devuelta por AWS.

```bash
REPO_URI="$(aws_demo ecr create-repository --repository-name "$S16_REPOSITORY" \
  --image-tag-mutability IMMUTABLE --tags Key=Project,Value=thepower-s16 \
  --query 'repository.repositoryUri' --output text)"
S16_REGISTRY="${REPO_URI%%/*}"
S16_IMAGE="$REPO_URI:1"
```

Autenticar Docker y subir la imagen preparada para AWS.

```bash
set -o pipefail
aws_demo ecr get-login-password | docker login --username AWS --password-stdin "$S16_REGISTRY"
docker tag s16-clasificador:1 "$S16_IMAGE"
docker push "$S16_IMAGE"
```

Generar una definición local con tus referencias de imagen, secreto, permisos y logs.

```bash
mkdir -p .demo-aws
cat > .demo-aws/task-definition.json <<JSON
{
  "family": "$S16_SERVICE",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$S16_EXECUTION_ROLE_ARN",
  "runtimePlatform": {"cpuArchitecture": "X86_64", "operatingSystemFamily": "LINUX"},
  "containerDefinitions": [{
    "name": "api",
    "image": "$S16_IMAGE",
    "essential": true,
    "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
    "environment": [
      {"name": "API_MODE", "value": "real"},
      {"name": "OPENROUTER_MODEL", "value": "openai/gpt-6-luna"},
      {"name": "OPENROUTER_PROVIDER", "value": "openai/fast"}
    ],
    "secrets": [{"name": "OPENROUTER_API_KEY", "valueFrom": "$S16_SECRET_ARN"}],
    "logConfiguration": {"logDriver": "awslogs", "options": {
      "awslogs-group": "$S16_LOG_GROUP", "awslogs-region": "$AWS_REGION", "awslogs-stream-prefix": "api"
    }},
    "healthCheck": {
      "command": ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()"],
      "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 20
    }
  }]
}
JSON
```

Registrar la configuración y guardar el ARN de la revisión creada.

```bash
S16_TASK_DEF_ARN="$(aws_demo ecs register-task-definition \
  --cli-input-json file://.demo-aws/task-definition.json \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
printf '%s\n' "$S16_TASK_DEF_ARN"
```

Permitir acceso al puerto de la demo solo desde tu IPv4 pública actual.

```bash
S16_IP="$(curl -4fsS https://checkip.amazonaws.com)"
S16_RULE_ID="$(aws_demo ec2 authorize-security-group-ingress \
  --group-id "$S16_SECURITY_GROUP" --protocol tcp --port 8000 --cidr "$S16_IP/32" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)"
```

Crear un servicio con una tarea y esperar al arranque en Fargate.

```bash
aws_demo ecs create-service --cluster "$S16_CLUSTER" --service-name "$S16_SERVICE" \
  --task-definition "$S16_TASK_DEF_ARN" --desired-count 1 --launch-type FARGATE \
  --platform-version 1.4.0 \
  --network-configuration "awsvpcConfiguration={subnets=[$S16_SUBNET],securityGroups=[$S16_SECURITY_GROUP],assignPublicIp=ENABLED}" \
  --deployment-configuration 'minimumHealthyPercent=0,maximumPercent=100,deploymentCircuitBreaker={enable=true,rollback=true}'
aws_demo ecs wait services-stable --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
```

Obtener la IP temporal de la tarea.

```bash
S16_TASK_ARN="$(aws_demo ecs list-tasks --cluster "$S16_CLUSTER" --service-name "$S16_SERVICE" \
  --desired-status RUNNING --query 'taskArns[0]' --output text)"
S16_ENI="$(aws_demo ecs describe-tasks --cluster "$S16_CLUSTER" --tasks "$S16_TASK_ARN" \
  --query 'tasks[0].attachments[].details[?name==`networkInterfaceId`].value[] | [0]' --output text)"
S16_PUBLIC_IP="$(aws_demo ec2 describe-network-interfaces --network-interface-ids "$S16_ENI" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"
```

Probar la API desde AWS y consultar los logs de CloudWatch.

```bash
curl --fail-with-body --connect-timeout 5 --max-time 10 "http://$S16_PUBLIC_IP:8000/health"
curl --fail-with-body --connect-timeout 5 --max-time 40 "http://$S16_PUBLIC_IP:8000/clasificar" \
  -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta ficticia"}'
aws_demo logs tail "$S16_LOG_GROUP" --since 30m
```

Al terminar, detener las tareas y eliminar el servicio y la revisión creados en esta práctica.

```bash
aws_demo sts get-caller-identity
aws_demo ecs update-service --cluster "$S16_CLUSTER" --service "$S16_SERVICE" --desired-count 0
aws_demo ecs wait services-stable --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
aws_demo ecs delete-service --cluster "$S16_CLUSTER" --service "$S16_SERVICE"
aws_demo ecs wait services-inactive --cluster "$S16_CLUSTER" --services "$S16_SERVICE"
aws_demo ecs deregister-task-definition --task-definition "$S16_TASK_DEF_ARN"
```

Eliminar el repositorio exclusivo de la práctica con todos sus manifiestos y cerrar la regla añadida.

```bash
aws_demo ecr delete-repository --repository-name "$S16_REPOSITORY" --force
aws_demo ec2 revoke-security-group-ingress --group-id "$S16_SECURITY_GROUP" \
  --security-group-rule-ids "$S16_RULE_ID"
```

Comprobar que no quedan tareas propias ni interfaces del grupo de la demo.

```bash
aws_demo ecs list-tasks --cluster "$S16_CLUSTER" --service-name "$S16_SERVICE" --desired-status RUNNING
aws_demo ec2 describe-network-interfaces --filters "Name=group-id,Values=$S16_SECURITY_GROUP" \
  --query 'NetworkInterfaces[].NetworkInterfaceId'
```

El cluster, logs y secreto preparados se conservan para repetir la práctica; revisa su coste y retira los recursos propios si ya no los necesitas. No borres recursos compartidos. El esquema de `.demo-aws/` contiene referencias de tu proyecto, no la clave; mantenlo fuera de Git.
