# Una imagen base de Python: misma arquitectura que la tarea de AWS.
FROM python:3.12-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
# Dependencias fijadas y verificadas por hash; copiar primero facilita reutilizar capas.
COPY requirements.lock .
RUN pip install --no-cache-dir --require-hashes -r requirements.lock \
    && groupadd --gid 10001 alumno && useradd --uid 10001 --gid alumno --no-create-home alumno
COPY --chown=10001:10001 app.py .
# La aplicación no necesita permisos de administrador.
USER 10001:10001
EXPOSE 8000
# 0.0.0.0 permite que Docker o ECS conecten con el proceso dentro del contenedor.
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
