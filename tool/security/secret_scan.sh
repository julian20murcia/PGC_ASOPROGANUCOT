#!/usr/bin/env bash
# PRUEBA DE SEGURIDAD — Búsqueda de secretos en el repositorio.
#
# Revisa TODOS los archivos versionados (git ls-files) en busca de claves que
# nunca deben subirse: claves de OpenAI, llaves privadas (cuentas de servicio,
# SSH), credenciales de AWS, tokens de GitHub/Slack y claves de Firebase fuera
# de los archivos de configuración donde Google indica que son públicas.
#
# Uso: bash tool/security/secret_scan.sh [archivo_reporte.md]
set -euo pipefail

REPORT="${1:-}"
cd "$(git rev-parse --show-toplevel)"

# patrón|descripción
PATTERNS=(
  'sk-(proj-|svcacct-)?[A-Za-z0-9_-]{20,}|Clave de API de OpenAI'
  '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|Llave privada'
  '"private_key"[[:space:]]*:|Cuenta de servicio de Google (JSON)'
  'AKIA[0-9A-Z]{16}|Credencial de AWS'
  'gh[pousr]_[A-Za-z0-9]{30,}|Token de GitHub'
  'xox[baprs]-[A-Za-z0-9-]{10,}|Token de Slack'
  'AIza[0-9A-Za-z_-]{35}|Clave de API de Google/Firebase'
)

# Las claves web de Firebase son identificadores públicos de la app (no dan
# acceso por sí solas; la seguridad está en firestore.rules). Se permiten SOLO
# en los archivos de configuración generados por FlutterFire.
ALLOW_GOOGLE_KEY_IN='^(lib/firebase_options\.dart|android/app/google-services\.json|ios/Runner/GoogleService-Info\.plist|macos/Runner/GoogleService-Info\.plist|functions/\.env\.[A-Za-z0-9_-]+)$'

FILES=$(git ls-files | grep -vE '\.(png|jpg|jpeg|gif|ico|pdf|ttf|otf|woff2?|zip|jar|lock)$|^tool/security/secret_scan\.sh$' || true)
TOTAL_FILES=$(printf '%s\n' "$FILES" | grep -c . || true)
FINDINGS=0
ALLOWED=0
OUT=""

for entry in "${PATTERNS[@]}"; do
  pattern="${entry%|*}"
  label="${entry##*|}"
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file="${hit%%:*}"
    if [[ "$label" == Clave\ de\ API\ de\ Google* ]] && [[ "$file" =~ $ALLOW_GOOGLE_KEY_IN ]]; then
      ALLOWED=$((ALLOWED + 1))
      continue
    fi
    FINDINGS=$((FINDINGS + 1))
    line="$(printf '%s' "$hit" | cut -d: -f2)"
    OUT+="| ${label} | \`${file}:${line}\` |"$'\n'
  done < <(printf '%s\n' "$FILES" | tr '\n' '\0' | xargs -0 grep -HnIE -- "$pattern" 2>/dev/null || true)
done

{
  echo "### Búsqueda de secretos"
  echo
  echo "- Archivos revisados: **${TOTAL_FILES}**"
  echo "- Patrones evaluados: **${#PATTERNS[@]}** (OpenAI, llaves privadas, cuentas de servicio, AWS, GitHub, Slack, Google)"
  echo "- Claves públicas de Firebase en archivos de configuración permitidos: ${ALLOWED}"
  echo "- Secretos encontrados: **${FINDINGS}**"
  if [ "$FINDINGS" -gt 0 ]; then
    echo
    echo "| Tipo | Ubicación |"
    echo "|---|---|"
    printf '%s' "$OUT"
  fi
} | tee ${REPORT:+"$REPORT"}

if [ "$FINDINGS" -gt 0 ]; then
  echo "::error::Se encontraron ${FINDINGS} posibles secretos en el repositorio." >&2
  exit 1
fi
