# Cargar desde la raíz del repositorio: source scripts/contexto.sh
if [ ! -f .demo-aws/contexto.sh ]; then
    echo 'Falta preparar AWS: sigue docs/preparar-aws.md.' >&2
    return 1
fi
source .demo-aws/contexto.sh
export AWS_PAGER='' AWS_CLI_AUTO_PROMPT=off
# Evita que Git Bash convierta nombres /s16/... en rutas de Windows.
export MSYS_NO_PATHCONV=1
aws_demo() { command aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"; }
s16_comprobar_identidad() {
    local actual
    actual="$(aws_demo sts get-caller-identity --query Account --output text)" || return 1
    if [ "$actual" != "$S16_PROJECT_ID" ]; then
        echo 'STOP: este no es el proyecto que preparaste.' >&2
        return 1
    fi
    aws_demo sts get-caller-identity
}
