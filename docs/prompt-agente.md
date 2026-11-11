# Desplegar, validar y limpiar con un agente

Prompt basado en la demo ensayada en clase. Sustituye los tres campos iniciales antes de copiarlo en Claude Code, Codex u otro agente con acceso a tu carpeta, Docker y AWS. Puede generar coste de infraestructura y hasta dos inferencias. El agente debe verificar sus herramientas y credenciales; no basta con pegar el texto en un chat sin acceso al equipo.

```text
Carpeta local del repositorio: <RUTA_DE_TU_CLON_DE_THEPOWER_AWS>
Perfil AWS autorizado: <TU_PERFIL>
ID del proyecto/cuenta autorizado: <TU_ID_AWS>
Región: eu-north-1 (sustituye por la región asignada a tu proyecto si es otra).

Ejecuta la demo completa de esta API: construcción Docker, publicación en ECR,
despliegue ECS/Fargate, clasificación real y limpieza. Explica cada fase con una
frase breve que pueda seguir un alumno. Lee las instrucciones del repositorio,
README.md y docs/guion-clase.md antes de empezar. No asumas que existen archivos
privados del profesor ni recursos en mi proyecto.

Verifica mi identidad, región y herramientas. Reutiliza los recursos de apoyo
que yo haya preparado siguiendo el README: cluster Fargate, rol de ejecución,
secreto de OpenRouter, logs, VPC y subred pública. Si falta alguno, indícame qué
falta antes de desplegar; no inventes identificadores ni uses los del profesor.
Si el perfil o ID inicial no está rellenado, pídemelo antes de crear recursos.
Si ha caducado la sesión, inicia el login y espera mi autenticación humana.

Te autorizo, solo en el proyecto y región indicados, a crear un repositorio ECR
propio para la demo, registrar una definición de tarea y lanzar un servicio con
una tarea Fargate de 0,25 vCPU y 512 MiB. También a abrir TCP 8000 solo desde mi
IPv4 pública /32 en un grupo de seguridad propio. No cambies facturación,
credenciales, permisos generales ni recursos compartidos.

1. Inspecciona el estado previo y registra los recursos que crearás. No
   interrumpas contenedores o servicios existentes. Usa nombres y versiones
   propios de la ejecución. Usa el MCP oficial si funciona; si no está
   disponible, utiliza el acceso local documentado con perfil y región explícitos.

2. Construye una imagen nativa para mi motor Docker y otra linux/amd64 para
   Fargate X86_64. Usa un contenedor y puerto locales libres. Pasa .env mediante
   --env-file y prueba /health y una clasificación real ficticia. Nunca muestres
   el archivo, claves, variables privadas, tokens ni el valor del secreto.

3. Publica la imagen de AWS en ECR autenticando Docker por stdin. Comprueba el
   digest y genera una definición temporal que use esa imagen por digest, el rol,
   secreto y logs correctos. API_MODE=real, OPENROUTER_MODEL=openai/gpt-6-luna y
   OPENROUTER_PROVIDER=openai/fast. La clave se referencia desde Secrets Manager;
   no la incorpores a la imagen ni a variables en texto plano en la definición.

4. Guarda las reglas previas de red, permite solo mi IP /32 y despliega con una
   tarea e IP pública temporal. Espera como máximo diez minutos al arranque;
   si falla, lee eventos y logs sin crear servicios duplicados.

5. Verifica la imagen realmente ejecutada, salud y una única clasificación real
   desde AWS con datos ficticios. Exige modo real, modelo esperado y JSON válido.
   Muestra el resultado y los logs antes de limpiar. No presentes simulaciones
   como inferencia real. Máximo dos inferencias: una local y otra desde AWS.

6. Limpia automáticamente lo creado por ti, también si falla una fase: detén y
   elimina tu servicio, desregistra tu revisión, retira tus imágenes/manifiestos y
   elimina ECR solo si creaste ese repositorio. Si existía, conserva las imágenes
   anteriores. Restaura las reglas originales y retira tu contenedor y etiquetas
   Docker temporales. Conserva todos los recursos de apoyo preexistentes.

7. Comprueba la retirada de tareas, servicio, interfaces y reglas añadidas. No
   declares limpieza completa si no la has verificado; si hay un bloqueo, indica
   qué permanece y si genera coste. No borres recursos ajenos para resolverlo.

Guarda DEMO-AGENTE-RESULTADO.md con pruebas reales, imagen/digest, revisión,
clasificación y estado final. No incluyas secretos. Distingue estimación de coste
y factura real. No hagas commit ni push. Resume qué funcionó y qué conservaste.
```
