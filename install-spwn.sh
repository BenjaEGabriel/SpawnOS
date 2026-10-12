#!/usr/bin/env bash
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Detect any available Python (3.x preferred, then python, then python2)
# ---------------------------------------------------------------------------
detect_python() {
    local candidates=(
        python3.15 python3.14 python3.13 python3.12 python3.11 python3.10
        python3.9 python3.8 python3.7 python3.6
        python3 python
        python2.7 python2
    )
    local c
    for c in "${candidates[@]}"; do
        if command -v "$c" >/dev/null 2>&1; then
            if "$c" -c "import sys; sys.exit(0)" 2>/dev/null; then
                echo "$c"
                return 0
            fi
        fi
    done
    return 1
}

PYTHON="$(detect_python || true)"
if [[ -z "${PYTHON:-}" ]]; then
    if command -v pkg >/dev/null 2>&1; then
        printf 'Instalando Python via pkg...\n'
        pkg install python -y || true
        PYTHON="$(detect_python || true)"
    fi
fi

if [[ -z "${PYTHON:-}" ]]; then
    printf 'Python 3 (ou 2) é necessário. Instale-o e execute novamente.\n'
    exit 1
fi

printf '\033[1;31mSPWN Language Installer\033[0m\n'
printf 'Usando: %s (%s)\n' "$PYTHON" "$("$PYTHON" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?')"

ROOT="${SPWN_HOME:-$HOME/SPWN}"
VERSION="0.3.0"

mkdir -p \
    "$ROOT/bin" \
    "$ROOT/etc" \
    "$ROOT/logs" \
    "$ROOT/tests" \
    "$ROOT/Def" \
    "$ROOT/Funcs" \
    "$ROOT/include" \
    "$ROOT/share/doc" \
    "$ROOT/data/packages" \
    "$ROOT/data/cache" \
    "$ROOT/data/registry" \
    "$ROOT/lib/spawn/stdlib" \
    "$ROOT/backend/Python" \
    "$ROOT/backend/Ruby" \
    "$ROOT/backend/JavaScript" \
    "$ROOT/backend/PHP" \
    "$ROOT/backend/Spawn"

if [[ ! -f "$ROOT/etc/version" ]]; then
    printf '%s\n' "$VERSION" > "$ROOT/etc/version"
fi

if [[ ! -f "$ROOT/changelog.spwn" ]]; then
    cat > "$ROOT/changelog.spwn" <<'LOG'
SPWN CHANGELOG

[0.3.0]
- Instalador modular.
- Estrutura de bibliotecas e backends.
- Diretórios de pacotes, testes e logs.
- Compatível com Python 2/3 e versões 3.6–3.15.
LOG
fi

if [[ ! -f "$ROOT/bin/spawn" ]]; then
    cat > "$ROOT/bin/spawn" <<'LAUNCHER'
#!/usr/bin/env bash
set -e
SPWN_HOME="${SPWN_HOME:-$HOME/SPWN}"
export SPWN_HOME

# Detect Python at runtime
_py() {
    for c in python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 \
             python3.9 python3.8 python3.7 python3.6 python3 python python2.7 python2; do
        command -v "$c" >/dev/null 2>&1 && echo "$c" && return
    done
    echo python
}
PY="$(_py)"

case "${1:-}" in
    --version|-v)
        printf 'SPWN %s\n' "$(cat "$SPWN_HOME/etc/version" 2>/dev/null || echo '?')"
        exit 0
        ;;
    --changelog)
        cat "$SPWN_HOME/changelog.spwn"
        exit 0
        ;;
    vault)
        shift
        exec "$PY" "$SPWN_HOME/lib/spawn/vault.py" "$@"
        ;;
esac

exec "$PY" "$SPWN_HOME/lib/spawn/runtime.py" "$@"
LAUNCHER
fi

chmod +x "$ROOT/bin/spawn"

# Add to PATH in common profile files
for profile in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    if [[ -f "$profile" ]] || [[ "$profile" == "$HOME/.profile" ]]; then
        if ! grep -qF 'SPWN/bin' "$profile" 2>/dev/null; then
            printf '\nexport PATH="$HOME/SPWN/bin:$PATH"\n' >> "$profile"
        fi
    fi
done

printf '\033[32mSPWN installation complete.\033[0m\n'
printf 'Root: %s\n' "$ROOT"

if [[ ! -f "$ROOT/lib/spawn/runtime.py" ]]; then
    printf '\033[33mRuntime não encontrado. Coloque runtime.py em lib/spawn/.\033[0m\n'
fi

printf 'Execute: export PATH="%s/bin:$PATH"\n' "$ROOT"
printf 'Teste: spawn --version\n'
