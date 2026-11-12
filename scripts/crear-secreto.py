"""Pide la clave sin mostrarla y la envía a AWS mediante un archivo temporal."""

import getpass
import os
import subprocess
import tempfile
from pathlib import Path

# El valor no aparece en argumentos del proceso, salida ni archivos del repositorio.
key = getpass.getpass("Clave OpenRouter (no se muestra): ").strip()
if not key:
    raise SystemExit("La clave está vacía.")
with tempfile.TemporaryDirectory(prefix="s16-secret-") as directory:
    path = Path(directory) / "key.txt"
    path.write_text(key)
    path.chmod(0o600)
    result = subprocess.run(
        [
            "aws",
            "--profile",
            os.environ["AWS_PROFILE"],
            "--region",
            os.environ["AWS_REGION"],
            "secretsmanager",
            "create-secret",
            "--name",
            os.environ["S16_SECRET_NAME"],
            "--secret-string",
            "file://" + str(path),
            "--tags",
            "Key=Project,Value=thepower-s16",
            "Key=ManagedBy,Value=thepower-student",
            "--query",
            "ARN",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise SystemExit(
            "No se creó el secreto. Revisa sesión, permisos y nombre libre. No se guardó la clave."
        )
    arn = result.stdout.strip()
    if not arn.startswith("arn:aws:secretsmanager:"):
        raise SystemExit("AWS no devolvió un identificador de secreto válido.")
    print(arn)
