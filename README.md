# S16 · Una API de IA en Docker y AWS

**Para repetir la demo de clase, sigue el [guion actualizado con todos los comandos](docs/guion-clase.md).** Si empiezas en tu propio proyecto AWS, completa primero [la preparación inicial por comandos](docs/preparar-aws.md): es lo que el profesor ya tenía preparado en el ensayo. Actualizado el 12/11/2026.

Vamos a llevar una pequeña API de soporte desde nuestro ordenador a AWS. El objetivo es entender **imagen → registro → contenedor → respuesta**, sin tener que estudiar un proyecto grande. La práctica posterior es opcional.

## Guías de la clase

- [0. Preparar AWS una vez: red, permisos, secreto, logs y cluster](docs/preparar-aws.md).
- [1. Guion del directo: subir, arrancar, probar y limpiar](docs/guion-clase.md).
- [2. Limpieza completa al terminar la práctica](docs/limpieza-completa.md).
- [Prompt para ejecutar la demo con un agente](docs/prompt-agente.md).

Las guías usan tu propio perfil, proyecto y recursos AWS. Prepara los requisitos indicados antes de ejecutar los bloques; el prompt requiere un agente con acceso a tu equipo y a AWS.

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

Necesitas el contenido de esta carpeta y Docker funcionando. En macOS y Windows abre Docker Desktop; en Windows selecciona contenedores Linux y utiliza Git Bash para ejecutar los comandos de esta guía. En Linux usa Docker Engine iniciado y una terminal Bash, con un usuario autorizado a ejecutar Docker; Docker Desktop también sirve. En macOS usa Terminal con Zsh o Bash. No necesitas instalar Python en tu equipo: la imagen ya lo incluye.

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
docker build -t s16-clasificador:local .
```

`docker build` lee el Dockerfile; `-t s16-clasificador:local` da nombre a la imagen; el punto final indica que la carpeta actual es el contexto de construcción. Sin `--platform`, Docker usa normalmente la arquitectura nativa del motor. La primera ejecución puede tardar mientras descarga la imagen base y las dependencias. Comprueba la imagen y su arquitectura:

```bash
docker image ls s16-clasificador
docker image inspect s16-clasificador:local --format '{{.Os}}/{{.Architecture}}'
```

El resultado suele ser `linux/arm64` en Mac con Apple Silicon y `linux/amd64` en equipos AMD64 con macOS, Linux o Windows. Un equipo Windows o Linux con procesador ARM puede mostrar `linux/arm64`. Depende de la arquitectura del motor Docker. La imagen usa Linux incluso en macOS y Windows.

### Paso 2: arrancar el contenedor simulado

```bash
docker run --rm -d --name s16-demo -p 127.0.0.1:8000:8000 s16-clasificador:local
docker ps
```

`--name` identifica el contenedor; `-d` lo deja ejecutándose en segundo plano; `--rm` lo elimina al detenerlo. `-p 127.0.0.1:8000:8000` conecta el puerto 8000 de tu ordenador con el 8000 del contenedor y limita el acceso local a tu equipo. La imagen se conserva después de parar el contenedor. En `docker ps` debe aparecer `s16-demo`.

### Paso 3: comprobar que funciona

```bash
curl --fail-with-body --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:8000/health
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
docker run --rm -d --name s16-demo --env-file .env -p 127.0.0.1:8000:8000 s16-clasificador:local
curl --fail-with-body --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/clasificar -H 'Content-Type: application/json' -d '{"texto":"No puedo entrar en mi cuenta"}'
docker logs s16-demo
docker stop s16-demo
```

La respuesta debe indicar `modo: real` y `openai/gpt-6-luna`. Usamos `OPENROUTER_PROVIDER=openai/fast` para solicitar expresamente el servicio rápido de OpenAI. **Es un modelo de pago**, también en modo rápido: revisa el precio y el presupuesto de tu cuenta antes de probarlo. Si el endpoint rápido falla o no está disponible, la API devolverá un error; no cambia de proveedor automáticamente. Para usar otro modelo, cambia `OPENROUTER_MODEL` por su ID exacto y selecciona un proveedor compatible en `OPENROUTER_PROVIDER` o déjalo vacío para permitir la selección normal de OpenRouter. Verifica que admita salidas estructuradas. No pongas claves en comandos, capturas ni repositorios.

Si cambias `.env`, detén y vuelve a crear el contenedor para que lea los nuevos valores. Si modificas `app.py` o las dependencias, construye de nuevo la imagen antes de arrancarlo. Un error 503 indica que falta la clave; un 502 puede indicar un problema con OpenRouter, el modelo o la validación de su respuesta. No publiques el contenido del archivo para pedir ayuda.

## 3. Subir la API a AWS como en clase

El recorrido completo está en una única guía para evitar comandos distintos entre documentos:

1. **[Preparar AWS una vez](docs/preparar-aws.md):** inicia sesión y crea tus recursos propios con comandos. Incluye lo que el profesor ya tenía preparado.
2. **[Seguir el guion del directo](docs/guion-clase.md):** construye la imagen AMD64, crea ECR, autentica Docker, sube la imagen, registra la configuración, abre tu IP, arranca Fargate, obtiene su IP y prueba la clasificación real. Incluye los comandos de logs, retirada y comprobación.
3. **[Retirar también la preparación](docs/limpieza-completa.md):** cuando no vayas a repetir, elimina tus recursos de apoyo y programa el borrado del secreto.

Usamos los mismos comandos y parámetros del ensayo, adaptados a los identificadores de cada alumno. El profesor utilizó archivos privados en `aws/`; aquí los auxiliares públicos están en `scripts/` y los JSON y datos de tu proyecto se generan en `.demo-aws/` (ignorada por Git). No necesitas `CLASE-AWS.md`, `aws/contexto.sh` ni ningún archivo fuera de este repo. No copies las direcciones o identificadores del proyecto del profesor.

El guion recupera de nuevo el identificador de la configuración antes de arrancar para evitar `TaskDefinition can not be blank`; calcula la IP nueva de cada tarea y busca la regla real al limpiar, aunque hayas perdido la variable.

La práctica es opcional. Usa mensajes ficticios, revisa los costes de AWS y OpenRouter y conserva pruebas de respuesta real y limpieza. El acceso HTTP limitado a tu IP es para esta prueba temporal; una API de producción necesita autenticación y TLS. Los errores reales nunca activan automáticamente el modo simulado.

Documentación: [ECS/Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html), [rol de ejecución](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html), [API Responses de OpenRouter](https://openrouter.ai/docs/api/reference/responses/overview).
