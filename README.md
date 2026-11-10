# S16 · Una API de IA en Docker y AWS

Vamos a llevar una pequeña API de soporte desde nuestro ordenador a AWS. El objetivo es entender **imagen → registro → contenedor → respuesta**, sin tener que estudiar un proyecto grande. La práctica posterior es opcional.

## Qué hace

`GET /health` comprueba que la API funciona. `POST /clasificar` recibe `{"texto":"No puedo entrar en mi cuenta"}` y devuelve categoría, prioridad y respuesta. `/docs` permite probarla desde el navegador.

Hay dos modos: `demo` devuelve un ejemplo simulado sin usar una clave; `real` llama a OpenRouter. El resultado indica el modo y, en real, el modelo que respondió. Una salud correcta no demuestra que el modelo funcione.

Archivos: `app.py` contiene la API y la llamada explicada paso a paso; `Dockerfile` crea la imagen; `requirements.lock` fija dependencias y hashes; `.dockerignore` evita copiar archivos privados.

En local, el recorrido es: **petición → API FastAPI en Docker → OpenRouter → modelo → respuesta JSON**. En AWS, ECR guarda la imagen y ECS/Fargate ejecuta el contenedor; Secrets Manager le proporciona la clave al arrancar.

Por ejemplo, una respuesta real tiene esta forma (el texto concreto puede variar):

```json
{
  "modo": "real",
  "modelo": "openai/gpt-6-luna",
  "resultado": {
    "categoria": "acceso",
    "prioridad": "media",
    "respuesta": "Prueba a restablecer el acceso a tu cuenta."
  }
}
```

La categoría puede ser `acceso`, `facturacion`, `tecnico` o `consulta`; la prioridad, `alta`, `media` o `baja`. La API valida esos valores y limita el texto de entrada a 1.000 caracteres.

## Variables de entorno

La aplicación lee estas variables al ejecutarse. Docker no carga `.env` automáticamente: se pasa con `--env-file .env` en el paso 2.

| Variable | Para qué sirve | Valor si no se configura |
|---|---|---|
| `API_MODE` | `demo` simula la respuesta; `real` llama a OpenRouter. | `demo` |
| `OPENROUTER_API_KEY` | Clave de OpenRouter; necesaria en modo real. | Sin valor; la clasificación real devuelve 503. |
| `OPENROUTER_MODEL` | Identificador del modelo en OpenRouter. | `openai/gpt-6-luna` |
| `OPENROUTER_PROVIDER` | Proveedor al que se limita la petición; `openai/fast` solicita el nivel rápido. | `openai/fast` |

En `.env.example` encontrarás un ejemplo para el modo real. Si dejas `OPENROUTER_PROVIDER=` vacío, la API permite la selección normal de proveedor de OpenRouter. El archivo `.env` es privado: no lo compartas ni lo subas al repositorio. En AWS se configura cada variable en la definición de tarea y la clave se referencia desde Secrets Manager.

## 1. Construir y probar Docker en local

### Antes de empezar

Necesitas el contenido de esta carpeta en tu ordenador y Docker Desktop instalado y abierto. Los comandos están escritos para una terminal Bash o Zsh; en Windows puedes usar una terminal Bash. No necesitas instalar Python en tu equipo: la imagen ya lo incluye.

Clona este repositorio y entra en su carpeta desde una terminal:

```bash
git clone https://github.com/JoseAntonioNuevo/thepower-aws.git
cd thepower-aws
```

Comprueba que estás en la carpeta correcta y que Docker responde:

```bash
pwd
ls -a
docker --version
docker info
```

En el listado deben aparecer `app.py`, `Dockerfile`, `requirements.lock` y `.env.example`. Si `docker info` dice que no puede conectarse al motor, abre Docker Desktop y espera a que termine de arrancar.

### Qué vamos a construir

Una **imagen** es el paquete de la aplicación; un **contenedor** es una ejecución de esa imagen. El `Dockerfile` de este proyecto es la receta:

1. Parte de una imagen de Python 3.12 y establece `/app` como carpeta de trabajo.
2. Copia `requirements.lock` e instala las dependencias con versiones y hashes fijados.
3. Crea un usuario sin permisos de administrador y copia `app.py`.
4. Indica que la aplicación usa el puerto 8000 y arranca Uvicorn para servir la API.

El archivo `.dockerignore` deja fuera `.env` y solo permite los archivos necesarios. `EXPOSE 8000` documenta el puerto del contenedor; la conexión con el ordenador se configura después con `docker run -p`.

### Paso 1: construir la imagen

```bash
docker build --platform linux/amd64 -t s16-clasificador:1 .
```

`docker build` lee el Dockerfile; `-t s16-clasificador:1` da nombre y versión a la imagen; el punto final indica que la carpeta actual es el contexto de construcción. La primera ejecución puede tardar mientras descarga la imagen base y las dependencias. Comprueba que la imagen aparece:

```bash
docker image ls s16-clasificador
```

Usamos `linux/amd64` para que coincida con la tarea X86_64 prevista en Fargate. En un Mac con Apple Silicon se necesita emulación para ejecutar esa imagen; también puedes usar ARM64 si construyes la imagen y configuras la tarea con la misma arquitectura.

### Paso 2: arrancar el contenedor simulado

```bash
docker run --rm -d --name s16-demo -p 127.0.0.1:8000:8000 s16-clasificador:1
docker ps
```

`--name` identifica el contenedor; `-d` lo deja ejecutándose en segundo plano; `--rm` lo elimina al detenerlo. `-p 127.0.0.1:8000:8000` conecta el puerto 8000 de tu ordenador con el 8000 del contenedor y limita el acceso local a tu equipo. La imagen se conserva después de parar el contenedor. En `docker ps` debe aparecer `s16-demo`.

### Paso 3: comprobar que funciona

```bash
curl http://127.0.0.1:8000/health
```

La respuesta esperada es `{"estado":"ok","modo":"demo"}`. Después, prueba la clasificación con una incidencia ficticia:

```bash
curl -X POST http://127.0.0.1:8000/clasificar -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta"}'
```

La respuesta contiene `"modo":"demo"` y un resultado simulado: todavía no se ha llamado a ningún modelo. También puedes abrir [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs) en el navegador y probar los endpoints desde la documentación interactiva.

Para consultar la salida de arranque y detener la prueba:

```bash
docker logs s16-demo
docker stop s16-demo
```

`docker ps` ya no debería mostrarlo. Si el puerto 8000 está ocupado, puedes arrancar con `-p 127.0.0.1:8016:8000` y usar `http://127.0.0.1:8016` en las pruebas. Si el nombre `s16-demo` ya existe, comprueba primero que es tuyo y detenlo con `docker stop s16-demo` antes de volver a arrancar.

## 2. Probar OpenRouter en local

Crea `.env` a partir del ejemplo **solo si todavía no existe**; si ya lo tienes, consérvalo. Edítalo y sustituye `pega_aqui_tu_clave` por tu clave sin comillas. No compartas `.env`, no lo subas a Git y no muestres su contenido en directo. Docker lo pasa solo al proceso; no se incorpora a la imagen. Estos comandos parten de la misma carpeta y de la imagen construida en el paso 1:

```bash
[ -e .env ] || cp .env.example .env
chmod 600 .env
# Edita .env con tu editor y guarda tu clave de OpenRouter.
docker run --rm -d --name s16-demo --env-file .env -p 127.0.0.1:8000:8000 s16-clasificador:1
curl -X POST http://127.0.0.1:8000/clasificar -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta"}'
docker logs s16-demo
docker stop s16-demo
```

La respuesta debe indicar `modo: real` y `openai/gpt-6-luna`. Usamos `OPENROUTER_PROVIDER=openai/fast` para solicitar expresamente el servicio rápido de OpenAI. **Es un modelo de pago**, también en modo rápido: revisa el precio y el presupuesto de tu cuenta antes de probarlo. Si el endpoint rápido falla o no está disponible, la API devolverá un error; no cambia de proveedor automáticamente. Para usar otro modelo, cambia `OPENROUTER_MODEL` por su ID exacto y selecciona un proveedor compatible en `OPENROUTER_PROVIDER` o déjalo vacío para permitir la selección normal de OpenRouter. Verifica que admita salidas estructuradas. No pongas claves en comandos, capturas ni repositorios.

Si cambias `.env`, detén y vuelve a crear el contenedor para que lea los nuevos valores. Si modificas `app.py` o las dependencias, construye de nuevo la imagen antes de arrancarlo. Un error 503 indica que falta la clave; un 502 puede indicar un problema con OpenRouter, el modelo o la validación de su respuesta. No publiques el contenido del archivo para pedir ayuda.

## 3. Publicar la imagen en ECR

Necesitas una cuenta AWS de laboratorio autorizada, AWS CLI con sesión ya configurada, permisos, región y presupuesto. Crear recursos genera costes. Comprueba cuenta y región antes de empezar; no envíes datos personales. El ejemplo usa Irlanda y un repositorio nuevo propio llamado `s16-clasificador`.

```bash
aws sts get-caller-identity
aws configure get region
# Sustituye por TU cuenta y región tras comprobarlas arriba.
AWS_ACCOUNT=123456789012
AWS_REGION=eu-west-1
REPO_URI="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/s16-clasificador"
aws ecr create-repository --repository-name s16-clasificador --region "$AWS_REGION"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com"
docker tag s16-clasificador:1 "$REPO_URI:1"
docker push "$REPO_URI:1"
```

En **ECR → Repositories → s16-clasificador → Images**, comprueba la etiqueta y el digest. Guardar la imagen en ECR todavía no ejecuta la API. Si el repositorio ya existe, no repitas su creación: verifica primero que es tuyo y que estás en la cuenta correcta.

## 4. Crear secreto y permisos

En **Secrets Manager**, crea un secreto de tipo «Other type of secret», en texto plano, con el valor completo de la clave de OpenRouter. Ponle un nombre propio, por ejemplo `s16/tu-nombre/openrouter`. Nunca lo muestres en pantalla ni lo escribas en la definición de la imagen. Copia solo su **ARN**.

Necesitas un **task execution role** para que ECS descargue la imagen, escriba logs y lea el secreto al arrancar. Además de `AmazonECSTaskExecutionRolePolicy`, añade a ese rol una política limitada a `secretsmanager:GetSecretValue` para el ARN del secreto. Si se usa una clave KMS propia, también hacen falta los permisos de descifrado y su política correspondiente. El **task role** es distinto: esta API no necesita llamar a APIs de AWS, por lo que no necesita permisos adicionales. Si no puedes crear o usar estos roles, pide al administrador del laboratorio un rol preparado; no concedas permisos generales para salir del paso.

## 5. Lanzar la API con ECS y Fargate

En la consola, mantén la misma cuenta y región:

1. En **CloudWatch → Log groups**, crea un grupo propio, por ejemplo `/s16/tu-nombre`, y fija una retención corta.
2. En **ECS → Clusters**, crea un cluster propio con infraestructura Fargate. Si ya tienes uno de laboratorio, verifica que puedes utilizarlo.
3. En **Task definitions**, crea una definición Fargate para Linux **X86_64**, 0,25 vCPU y 0,5 GB de memoria. Selecciona el execution role anterior. Añade un contenedor con la URI de la imagen ECR y puerto TCP **8000**. Activa logs con el grupo creado, región y prefijo `api`.
4. En las variables del contenedor, añade `API_MODE=real`, `OPENROUTER_MODEL=openai/gpt-6-luna` y `OPENROUTER_PROVIDER=openai/fast`. Añade `OPENROUTER_API_KEY` como **secreto de Secrets Manager**, indicando su ARN en el campo de referencia; no pegues el valor. La tarea recupera el secreto al arrancar.
5. En el cluster crea un **servicio** Fargate con esa definición y una tarea deseada. Para esta prueba usa una VPC y subred pública con ruta a internet gateway, asignación de IP pública y un security group con entrada TCP 8000 **solo desde tu IP pública /32**. Permite la salida HTTPS 443 necesaria y asegúrate de que DNS y las rutas funcionen. No abras el puerto a todo Internet. Consulta tu IP por un medio conocido antes de crear la regla; una VPN puede cambiarla.
6. Espera a que la tarea esté `RUNNING` y consulta su IP pública en **Tasks → Networking**. Una tarea puede tardar varios minutos; revisa Events y CloudWatch si no arranca.

La IP y HTTP son para una **prueba temporal restringida**, con datos ficticios y sin claves de clientes. No es una configuración de producción ni proporciona autenticación o TLS para quienes llaman a la API. Si estás compartiendo pantalla, evita revelar secretos.

## 6. Comprobar y retirar

Desde la IP permitida, sustituye `IP_DE_LA_TAREA`:

```bash
curl http://IP_DE_LA_TAREA:8000/health
curl -X POST http://IP_DE_LA_TAREA:8000/clasificar -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta"}'
```

Comprueba `modo: real`, el modelo y la respuesta. En CloudWatch abre el grupo y el stream de la tarea para revisar arranque y errores. Si `/health` funciona y falla `/clasificar`, revisa el modelo, acceso a OpenRouter, secreto y salida HTTPS. Un 502 significa que la llamada o la respuesta no se pudo validar; no revela la clave ni el error remoto.

Al terminar, elimina **solo los recursos propios**: servicio y tareas, cluster si se creó para la prueba, definición de tarea cuando ya no se use, imágenes y repositorio ECR, grupo de logs y secreto. Revisa red, interfaces e IPs creadas; conserva VPC, roles y demás recursos compartidos. Secrets Manager puede programar el borrado para una fecha futura: comprueba su estado. Revisa costes en Billing. Parar tareas no borra imágenes, logs ni secretos; pueden seguir generando coste. Estima por separado 730 horas de Fargate, IPv4, ECR, logs, secreto, tráfico e inferencia; las alertas de presupuesto no paran recursos automáticamente.

## Para la clase

Enseñar primero el resultado local; después mostrar `app.py`, el Dockerfile y el trayecto ECR → ECS/Fargate. Preparar previamente permisos, red, presupuesto y secreto; ensayar publicación, llamada real y retirada en la cuenta autorizada. Si AWS o OpenRouter fallan, mostrar `demo` como simulación, sin presentarlo como una llamada real. Para la práctica, el alumno repite el recorrido y documenta imagen, respuesta, coste y limpieza.

Documentación: [API Responses de OpenRouter](https://openrouter.ai/docs/api/reference/responses/overview), [niveles de servicio](https://openrouter.ai/docs/guides/features/service-tiers), [salidas estructuradas](https://openrouter.ai/docs/guides/features/structured-outputs).
