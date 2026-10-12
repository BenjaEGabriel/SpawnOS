#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${SPWN_BASE_URL:-https://SEU-WORKER.workers.dev}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ "$BASE_URL" == *"SEU-WORKER"* ]]; then
    printf 'Define SPWN_BASE_URL com a URL real do teu Worker.\n' >&2
    exit 1
fi

printf '\n  ✦ SPWN + SpawnOS Installer\n'
printf '  Origem: %s\n\n' "$BASE_URL"

for script in Install-spwn.sh Install-spawnos.sh; do
    printf '[1/2] Baixando %s...\n' "$script"
    curl --fail --location --silent --show-error \
        "$BASE_URL/$script" -o "$TMP/$script"
done

export SPWN_BASE_URL="$BASE_URL"

printf '\n[2/2] Instalando SPWN...\n'
bash "$TMP/Install-spwn.sh"

printf '\n[2/2] Instalando SpawnOS...\n'
bash "$TMP/Install-spawnos.sh"

printf '\nInstalação concluída!\n'
printf 'Executa: export PATH="$HOME/SPWN/bin:$PATH" && spawnos\n'