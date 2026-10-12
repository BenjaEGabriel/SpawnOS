#!/usr/bin/env bash
# Compatible with Termux and regular Linux
# Works with any Python detected by the child installers

set -e

echo "instalando..."
sleep 1

# Prefer bash from PATH; fall back to common Termux location
BASH_BIN="$(command -v bash 2>/dev/null || echo /data/data/com.termux/files/usr/bin/bash)"

if [[ -f ./install-spwn.sh ]]; then
    "$BASH_BIN" ./install-spwn.sh
elif [[ -f install-spwn.sh ]]; then
    "$BASH_BIN" install-spwn.sh
else
    echo "install-spwn.sh não encontrado"
    exit 1
fi

echo "Linguagem SPWN implementada"
sleep 1

if [[ -f ./install-spawnos.sh ]]; then
    "$BASH_BIN" ./install-spawnos.sh
elif [[ -f install-spawnos.sh ]]; then
    "$BASH_BIN" install-spawnos.sh
else
    echo "install-spawnos.sh não encontrado"
    exit 1
fi

echo "Sistema Instalado"
sleep 1

# Reload shell config if present
if [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.bashrc" 2>/dev/null || true
elif [[ -f "$HOME/.profile" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.profile" 2>/dev/null || true
fi

echo "[OK] Instalação finalizada. Digite: spawnos"
