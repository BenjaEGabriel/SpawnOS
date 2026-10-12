#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${SPWN_HOME:-$HOME/SPWN}"
VERSION="0.3.0"

printf '\033[1;31mSPWN Language Installer\033[0m\n'

if ! command -v python >/dev/null 2>&1; then
    if command -v pkg >/dev/null 2>&1; then
        pkg install python -y
    else
        printf 'Python 3 é necessário. Instale-o e execute novamente.\n'
        exit 1
    fi
fi

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
LOG
fi

if [[ ! -f "$ROOT/bin/spawn" ]]; then
    cat > "$ROOT/bin/spawn" <<'LAUNCHER'
#!/usr/bin/env bash
set -e
SPWN_HOME="${SPWN_HOME:-$HOME/SPWN}"
export SPWN_HOME

case "${1:-}" in
    --version|-v)
        printf 'SPWN %s\n' "$(cat "$SPWN_HOME/etc/version")"
        exit 0
        ;;
    --changelog)
        cat "$SPWN_HOME/changelog.spwn"
        exit 0
        ;;
    vault)
        shift
        exec python "$SPWN_HOME/lib/spawn/vault.py" "$@"
        ;;
esac

exec python "$SPWN_HOME/lib/spawn/runtime.py" "$@"
LAUNCHER
fi

chmod +x "$ROOT/bin/spawn"

if ! grep -qF 'SPWN/bin' "$HOME/.profile" 2>/dev/null; then
    printf '\nexport PATH="$HOME/SPWN/bin:$PATH"\n' >> "$HOME/.profile"
fi

printf '\033[32mSPWN installation complete.\033[0m\n'
printf 'Root: %s\n' "$ROOT"

if [[ ! -f "$ROOT/lib/spawn/runtime.py" ]]; then
    printf '\033[33mRuntime não encontrado. Coloque runtime.py em lib/spawn/.\033[0m\n'
fi

printf 'Execute: export PATH="%s/bin:$PATH"\n' "$ROOT"
printf 'Teste: spawn --version\n'
