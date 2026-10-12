#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${SPWN_HOME:-$HOME/SPWN}"
BASE_URL="${SPWN_BASE_URL:-https://SEU-WORKER.workers.dev}"
ARCHIVE_URL="${SPWN_ARCHIVE_URL:-$BASE_URL/releases/spwn.tar.gz}"

die() { printf '\n[ERRO] %s\n' "$*" >&2; exit 1; }
info() { printf '[SPWN] %s\n' "$*"; }

[[ "$BASE_URL" != *"SEU-WORKER"* ]] ||
    die "Define SPWN_BASE_URL com a URL real do teu Worker."

command -v curl >/dev/null 2>&1 || die "Instala curl primeiro."
command -v tar >/dev/null 2>&1 || die "O comando tar é necessário."

if command -v python3 >/dev/null 2>&1; then
    PYTHON="$(command -v python3)"
elif command -v python >/dev/null 2>&1; then
    PYTHON="$(command -v python)"
else
    die "Python não encontrado. Instala Python 3 e tenta novamente."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Baixando os componentes oficiais..."
curl --fail --location --silent --show-error \
    "$ARCHIVE_URL" -o "$TMP/spwn.tar.gz" ||
    die "Não foi possível baixar $ARCHIVE_URL"

tar -tzf "$TMP/spwn.tar.gz" > "$TMP/files.txt" ||
    die "O arquivo recebido não é um tar.gz válido."

if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TMP/files.txt"; then
    die "O arquivo contém caminhos inseguros."
fi

mkdir -p "$TMP/stage"
tar -xzf "$TMP/spwn.tar.gz" -C "$TMP/stage"

# Aceita arquivo na raiz do pacote ou dentro de uma pasta SPWN/.
if [[ -x "$TMP/stage/bin/spawn" ]]; then
    SRC="$TMP/stage"
else
    SRC=""
    while IFS= read -r candidate; do
        if [[ -x "$candidate/bin/spawn" ]]; then
            SRC="$candidate"
            break
        fi
    done < <(find "$TMP/stage" -type f -path '*/bin/spawn' -printf '%h\n' 2>/dev/null |
             sed 's#/bin$##')
fi

[[ -n "$SRC" && -f "$SRC/bin/spawn" ]] ||
    die "Pacote sem bin/spawn. Verifica o conteúdo do arquivo."
[[ -f "$SRC/lib/spawn/runtime.py" ]] ||
    die "Pacote sem lib/spawn/runtime.py. Runtime incompleto."

info "Preparando $ROOT..."
mkdir -p "$ROOT"/{bin,lib/spawn,etc,logs,data,installers,backend,Def,Funcs}

# Copia somente os componentes da linguagem, sem apagar o projeto inteiro.
cp -a "$SRC/bin/spawn" "$ROOT/bin/spawn"
cp -a "$SRC/lib/spawn/." "$ROOT/lib/spawn/"
[[ ! -d "$SRC/backend" ]] || cp -an "$SRC/backend/." "$ROOT/backend/"
[[ ! -d "$SRC/Def" ]] || cp -an "$SRC/Def/." "$ROOT/Def/"
[[ ! -d "$SRC/Funcs" ]] || cp -an "$SRC/Funcs/." "$ROOT/Funcs/"
[[ ! -f "$ROOT/etc/version" && ! -f "$SRC/etc/version" ]] &&
    printf '0.1.0-beta\n' > "$ROOT/etc/version"
[[ ! -f "$SRC/etc/version" ]] ||
    cp -n "$SRC/etc/version" "$ROOT/etc/version"

chmod +x "$ROOT/bin/spawn"

PROFILE="$HOME/.profile"
touch "$PROFILE"
if ! grep -qF 'export PATH="$HOME/SPWN/bin:$PATH"' "$PROFILE"; then
    printf '\nexport PATH="$HOME/SPWN/bin:$PATH"\n' >> "$PROFILE"
fi

info "SPWN instalado."
info "Ativa com: export PATH=\"$ROOT/bin:\$PATH\""
info "Testa com: spawn --version"