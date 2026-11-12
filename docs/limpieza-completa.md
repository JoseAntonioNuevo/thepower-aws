# Limpieza completa · Cuando ya no vas a repetir

Solo para los recursos propios creados con [Preparar AWS](preparar-aws.md). No ejecutes estos comandos sobre recursos prestados o compartidos. Primero termina el **paso 7 y las comprobaciones del paso 8 del [guion](guion-clase.md)**. Si queda una interfaz de red, espera a que desaparezca antes de borrar la red.

**Recupera tu configuración y comprueba el proyecto.**

```bash
source scripts/contexto.sh
s16_comprobar_identidad
```

**Retira todas las revisiones de configuración de esta familia propia; no consumen CPU, pero ya no las usaremos.**

```bash
for S16_REVISION in $(aws_demo ecs list-task-definitions --family-prefix "$S16_SERVICE" --status ACTIVE --query 'taskDefinitionArns[]' --output text); do
  case "$S16_REVISION" in
    *"task-definition/$S16_SERVICE:"*) aws_demo ecs deregister-task-definition --task-definition "$S16_REVISION" ;;
  esac
done
```

**Borra el cluster vacío, sus registros y el rol de ejecución propio.**

```bash
aws_demo ecs delete-cluster --cluster "$S16_CLUSTER"
aws_demo logs delete-log-group --log-group-name "$S16_LOG_GROUP"
aws_demo iam delete-role-policy --role-name "$S16_EXECUTION_ROLE" --policy-name s16-runtime-only
aws_demo iam delete-role --role-name "$S16_EXECUTION_ROLE"
```

**Programa el borrado del secreto con siete días de recuperación; no se borra inmediatamente.**

```bash
aws_demo secretsmanager delete-secret --secret-id "$S16_SECRET_ARN" --recovery-window-in-days 7
```

**Retira el grupo de acceso y la subred de esta práctica.**

```bash
aws_demo ec2 delete-security-group --group-id "$S16_SECURITY_GROUP"
aws_demo ec2 disassociate-route-table --association-id "$S16_ROUTE_ASSOC"
aws_demo ec2 delete-subnet --subnet-id "$S16_SUBNET"
```

**Retira la salida de Internet y termina de borrar la red propia.**

```bash
aws_demo ec2 delete-route-table --route-table-id "$S16_ROUTE_TABLE"
aws_demo ec2 detach-internet-gateway --internet-gateway-id "$S16_IGW" --vpc-id "$S16_VPC"
aws_demo ec2 delete-internet-gateway --internet-gateway-id "$S16_IGW"
aws_demo ec2 delete-vpc --vpc-id "$S16_VPC"
```

Si algo falla, detente y comprueba qué recurso sigue existiendo; no borres recursos ajenos para resolverlo. Conserva `.demo-aws/contexto.sh` hasta verificar la retirada de tus recursos en la consola AWS. Revisa Billing: los costes no aparecen necesariamente de inmediato. Para volver a empezar después de esta limpieza necesitarás un nombre nuevo mientras el secreto anterior esté pendiente de borrado.
