"""Genera JSON de la demo con tus identificadores; no lee ni guarda la clave."""

import json
import os
from pathlib import Path


def required(name):
    value = os.environ.get(name, "")
    if not value or value == "None":
        raise SystemExit(f"Falta {name}: carga scripts/contexto.sh")
    return value


folder = Path(".demo-aws")
folder.mkdir(exist_ok=True)
account = required("S16_PROJECT_ID")
region = required("AWS_REGION")
role = required("S16_EXECUTION_ROLE")
secret = required("S16_SECRET_ARN")
logs = required("S16_LOG_GROUP")
repo = required("S16_REPOSITORY")
service = required("S16_SERVICE")


def save(name, value):
    (folder / name).write_text(json.dumps(value, indent=2) + "\n")


task = {
    "family": "s16-ejemplo-api",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::123456789012:role/s16-ejemplo-ecs-execution",
    "runtimePlatform": {"cpuArchitecture": "X86_64", "operatingSystemFamily": "LINUX"},
    "containerDefinitions": [
        {
            "name": "api",
            "image": "123456789012.dkr.ecr.eu-north-1.amazonaws.com/s16-clasificador:1",
            "essential": True,
            "portMappings": [{"containerPort": 8000, "protocol": "tcp", "appProtocol": "http"}],
            "environment": [
                {"name": "API_MODE", "value": "real"},
                {"name": "OPENROUTER_MODEL", "value": "openai/gpt-6-luna"},
                {"name": "OPENROUTER_PROVIDER", "value": "openai/fast"},
            ],
            "secrets": [
                {
                    "name": "OPENROUTER_API_KEY",
                    "valueFrom": "REFERENCIA_GENERADA",
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/s16/thepower/api",
                    "awslogs-region": "eu-north-1",
                    "awslogs-stream-prefix": "api",
                    "mode": "non-blocking",
                    "max-buffer-size": "1m",
                },
            },
            "healthCheck": {
                "command": [
                    "CMD",
                    "python",
                    "-c",
                    "import urllib.request; "
                    "urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()",
                ],
                "interval": 30,
                "timeout": 5,
                "retries": 3,
                "startPeriod": 20,
            },
            "readonlyRootFilesystem": True,
        }
    ],
    "tags": [
        {"key": "Project", "value": "thepower-s16"},
        {"key": "Purpose", "value": "classroom-demo"},
    ],
}
container = task["containerDefinitions"][0]
task["family"] = service
task["executionRoleArn"] = f"arn:aws:iam::{account}:role/{role}"
container["image"] = required("S16_IMAGE")
container["secrets"][0]["valueFrom"] = secret
container["logConfiguration"]["options"]["awslogs-group"] = logs
container["logConfiguration"]["options"]["awslogs-region"] = region
save("task-definition.json", task)
save(
    "network.json",
    {
        "awsvpcConfiguration": {
            "subnets": [required("S16_SUBNET")],
            "securityGroups": [required("S16_SECURITY_GROUP")],
            "assignPublicIp": "ENABLED",
        }
    },
)
save(
    "trust.json",
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "ecs-tasks.amazonaws.com"},
                "Action": "sts:AssumeRole",
                "Condition": {
                    "StringEquals": {"aws:SourceAccount": account},
                    "ArnLike": {"aws:SourceArn": f"arn:aws:ecs:{region}:{account}:*"},
                },
            }
        ],
    },
)
save(
    "permissions.json",
    {
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
            {
                "Effect": "Allow",
                "Action": [
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                "Resource": f"arn:aws:ecr:{region}:{account}:repository/{repo}",
            },
            {
                "Effect": "Allow",
                "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
                "Resource": f"arn:aws:logs:{region}:{account}:log-group:{logs}:log-stream:api/*",
            },
            {"Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"], "Resource": secret},
        ],
    },
)
print("JSON preparados en .demo-aws/; no contienen el valor de la clave.")
