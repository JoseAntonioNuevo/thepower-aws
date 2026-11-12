# Preparar AWS una vez · Lo que el profesor ya tenía listo

Esta preparación deja tu proyecto en el mismo punto de partida de la clase: **red, cluster, permisos, logs y clave preparados; ninguna API arrancada**. Después sigue [el guion del directo](guion-clase.md).

Usa tu propio proyecto autorizado, con permisos para crear estos recursos y pasar el rol a ECS (`iam:PassRole`). Si el laboratorio no permite IAM o VPC, el administrador debe preparar esta parte. No uses identificadores del profesor. Genera costes de secreto y registros; más adelante Fargate, IPv4 e inferencia. No cambies de plan para resolver un error sin revisar su causa.

Necesitas Git, Docker iniciado, AWS CLI v2 reciente, Python 3 y una clave OpenRouter. En Mac/Linux usa **Bash** (`bash`); en Windows usa **Git Bash**, contenedores Linux y Python instalado con el comando `python3` disponible. Si Windows solo ofrece `python`, usa `python` en lugar de `python3` en los comandos y scripts `.sh` de esta guía. No uses PowerShell para copiar estos bloques. No actives `set -x` ni compartas la clave.

## 1. Descargar y entrar

**Descarga la API y entra en su carpeta; si ya la tienes, usa tu carpeta actual.**

```bash
git clone https://github.com/JoseAntonioNuevo/thepower-aws.git
cd thepower-aws
```

Si ya clonaste el repositorio, actualízalo con `git pull --ff-only` antes de continuar; conserva tu `.env` privado.

**Comprueba las herramientas.**

```bash
aws --version
docker info
python3 --version
```

## 2. Iniciar sesión y elegir tus nombres

**Cambia `tu-perfil` y `123456789012` por tu perfil y el ID de tu proyecto; `s16-alumna` debe ser un nombre propio libre, solo letras minúsculas, números y guiones.**

```bash
export AWS_PROFILE=tu-perfil
export AWS_REGION=eu-north-1
export S16_PROJECT_ID=123456789012
export S16_NAME=s16-alumna
export AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off MSYS_NO_PATHCONV=1
set -o pipefail
aws_demo() { command aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"; }
```

Estocolmo es la región de clase; usa la región asignada a tu proyecto si es otra. En la nueva experiencia puedes verla en AWS Settings → View all projects → Overview → Additional Info → Region.

**Si todavía no has iniciado sesión con la nueva experiencia, abre el navegador y complétala.** Si tu organización usa IAM Identity Center, utiliza su inicio de sesión (`aws sso login --profile "$AWS_PROFILE"`) en lugar de `aws login`.

```bash
aws login --profile "$AWS_PROFILE" --region "$AWS_REGION"
```

**Comprueba que vas a trabajar en tu proyecto antes de crear nada.**

```bash
S16_ACTUAL="$(aws_demo sts get-caller-identity --query Account --output text)"
[ "$S16_ACTUAL" = "$S16_PROJECT_ID" ] && echo 'Proyecto correcto'
```

Si no imprime `Proyecto correcto`, detente y revisa el perfil y el ID.

**Guarda los nombres en un archivo privado para no perderlos al cambiar de terminal.**

```bash
export S16_CLUSTER="$S16_NAME"
export S16_SERVICE="$S16_NAME-api"
export S16_REPOSITORY="$S16_NAME-clasificador"
export S16_REGISTRY="$S16_PROJECT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
export S16_IMAGE="$S16_REGISTRY/$S16_REPOSITORY:1"
export S16_EXECUTION_ROLE="$S16_NAME-execution"
export S16_SECRET_NAME="s16/$S16_NAME/openrouter"
export S16_LOG_GROUP="/s16/$S16_NAME/api"
bash scripts/guardar-contexto.sh
source scripts/contexto.sh
s16_comprobar_identidad
```

Desde aquí, **detente si falla cualquier bloque**. No repitas la preparación sobre recursos que ya has creado. Si interrumpes el proceso, carga `source scripts/contexto.sh` y continúa desde el primer bloque pendiente.

## 3. Preparar una red propia

Creamos una red independiente para no cambiar redes compartidas. En clase esta red ya estaba preparada; no hace falta NAT, balanceador ni servidor EC2.

**Crea la red donde se conectará la aplicación.**

```bash
S16_VPC="$(aws_demo ec2 create-vpc --cidr-block 10.16.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$S16_NAME},{Key=Project,Value=thepower-s16}]" \
  --query 'Vpc.VpcId' --output text)"
export S16_VPC
bash scripts/guardar-contexto.sh
aws_demo ec2 wait vpc-available --vpc-ids "$S16_VPC"
aws_demo ec2 modify-vpc-attribute --vpc-id "$S16_VPC" --enable-dns-support '{"Value":true}'
```

**Crea una subred con espacio para las direcciones de la aplicación.**

```bash
S16_SUBNET="$(aws_demo ec2 create-subnet --vpc-id "$S16_VPC" --cidr-block 10.16.1.0/24 \
  --query 'Subnet.SubnetId' --output text)"
export S16_SUBNET
bash scripts/guardar-contexto.sh
aws_demo ec2 wait subnet-available --subnet-ids "$S16_SUBNET"
```

**Añade una puerta de salida a Internet para descargar la imagen y llamar a OpenRouter.**

```bash
S16_IGW="$(aws_demo ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)"
export S16_IGW
bash scripts/guardar-contexto.sh
aws_demo ec2 attach-internet-gateway --internet-gateway-id "$S16_IGW" --vpc-id "$S16_VPC"
```

**Indica a la subred que use esa salida para llegar a Internet.**

```bash
S16_ROUTE_TABLE="$(aws_demo ec2 create-route-table --vpc-id "$S16_VPC" --query 'RouteTable.RouteTableId' --output text)"
export S16_ROUTE_TABLE
bash scripts/guardar-contexto.sh
aws_demo ec2 create-route --route-table-id "$S16_ROUTE_TABLE" --destination-cidr-block 0.0.0.0/0 --gateway-id "$S16_IGW"
S16_ROUTE_ASSOC="$(aws_demo ec2 associate-route-table --route-table-id "$S16_ROUTE_TABLE" --subnet-id "$S16_SUBNET" --query AssociationId --output text)"
export S16_ROUTE_ASSOC
bash scripts/guardar-contexto.sh
```

**Crea un control de acceso propio, inicialmente sin entradas.**

```bash
S16_SECURITY_GROUP="$(aws_demo ec2 create-security-group --group-name "$S16_SERVICE" \
  --description 'API temporal S16' --vpc-id "$S16_VPC" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Project,Value=thepower-s16},{Key=ManagedBy,Value=thepower-student}]' \
  --query GroupId --output text)"
export S16_SECURITY_GROUP
bash scripts/guardar-contexto.sh
```

**Sustituye la salida general que AWS añade por defecto por salida HTTPS.**

```bash
aws_demo ec2 revoke-security-group-egress --group-id "$S16_SECURITY_GROUP" \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
aws_demo ec2 authorize-security-group-egress --group-id "$S16_SECURITY_GROUP" \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
```

## 4. Guardar la clave y preparar registros

**Pide tu clave sin mostrarla, crea el secreto y guarda solo su identificador.** El script elimina el archivo temporal incluso si AWS falla; no escribe la clave en el repositorio ni en los argumentos del comando.

```bash
S16_SECRET_ARN="$(python3 scripts/crear-secreto.py)"
export S16_SECRET_ARN
[ -n "$S16_SECRET_ARN" ] && bash scripts/guardar-contexto.sh
```

Si falla o queda vacío, detente. No sustituyas este paso pegando la clave en un comando. La API de clase usa `openai/gpt-6-luna` con `openai/fast`, que genera consumo de pago en OpenRouter.

**Crea el lugar donde veremos los mensajes de arranque y conserva solo tres días.**

```bash
aws_demo logs create-log-group --log-group-name "$S16_LOG_GROUP"
aws_demo logs put-retention-policy --log-group-name "$S16_LOG_GROUP" --retention-in-days 3
```

## 5. Preparar los permisos de la aplicación

**Genera los JSON con tus identificadores; contienen referencias, nunca la clave.**

```bash
python3 scripts/preparar-json.py
```

**Crea un rol que ECS podrá usar para descargar la imagen, leer la clave y escribir los mensajes.**

```bash
aws_demo iam create-role --role-name "$S16_EXECUTION_ROLE" \
  --assume-role-policy-document file://.demo-aws/trust.json \
  --tags Key=Project,Value=thepower-s16 Key=ManagedBy,Value=thepower-student
aws_demo iam put-role-policy --role-name "$S16_EXECUTION_ROLE" --policy-name s16-runtime-only \
  --policy-document file://.demo-aws/permissions.json
```

El rol tiene permisos limitados a tus recursos; la API no necesita un segundo rol para llamar a AWS. Los permisos IAM pueden tardar un poco en propagarse.

## 6. Preparar el cluster

**Crea el grupo donde AWS organizará las ejecuciones con Fargate, sin arrancar ninguna.**

```bash
aws_demo ecs create-cluster --cluster-name "$S16_CLUSTER" --capacity-providers FARGATE \
  --tags key=Project,value=thepower-s16 key=Purpose,value=classroom-demo
```

**Comprueba el punto de partida: ninguna tarea y ninguna entrada abierta.**

```bash
aws_demo ecs describe-clusters --clusters "$S16_CLUSTER" \
  --query 'clusters[].{tareas:runningTasksCount,servicios:activeServicesCount}'
aws_demo ec2 describe-security-groups --group-ids "$S16_SECURITY_GROUP" \
  --query 'SecurityGroups[0].IpPermissions'
```

Esperado: cero tareas/servicios y `[]`. Continúa con [el guion del directo](guion-clase.md). Al terminar puedes repetirlo conservando esta preparación o [retirarla por completo](limpieza-completa.md).
