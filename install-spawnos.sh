#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${SPWN_HOME:-$HOME/SPWN}"
OS="$ROOT/SpawnOS"
BIN="$ROOT/bin"
ETC="$ROOT/etc"
CONFIG="$ETC/spawnos.json"
SELF="${BASH_SOURCE[0]}"

mkdir -p "$OS/home" "$OS/apps" "$OS/tmp" "$BIN" "$ETC" "$ROOT/logs"

if ! command -v python >/dev/null 2>&1; then
    printf 'Python 3 é necessário para instalar a SpawnOS.\n'
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    ROOT_PATH="$ROOT" python - <<'PY'
import json, os
from pathlib import Path
p = Path(os.environ["ROOT_PATH"]) / "etc/spawnos.json"
p.write_text(json.dumps({
    "name": "SpawnOS",
    "username": "",
    "prompt": "{name}@{username}: $ {cwd}",
    "theme": "Crimson",
    "language": "Português",
    "startup": True,
    "color": True,
    "allow_external": True
}, indent=2), encoding="utf-8")
PY
fi

if [[ ! -f "$OS/installed" ]]; then
    printf 'SpawnOS 0.1.0-beta\n' > "$OS/installed"
fi

if [[ ! -f "$ROOT/lib/spawn/os_shell.py" ]]; then
    cat > "$ROOT/lib/spawn/os_shell.py" <<'PY'
import json, os, shlex, subprocess
from pathlib import Path

ROOT = Path(os.environ.get("SPWN_HOME", str(Path.home() / "SPWN")))
CONFIG = ROOT / "etc/spawnos.json"
cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
cwd = Path.cwd()

def prompt():
    return cfg["prompt"].format(
        name=cfg.get("name", "SpawnOS"),
        username=cfg.get("username", "User"),
        cwd=str(cwd),
        session="LOCAL"
    )

def main():
    global cwd
    print("SpawnOS 0.1.0-beta")
    while True:
        try:
            line = input(prompt())
            a = shlex.split(line)
            if not a:
                continue
            cmd, *args = a
            if cmd in ("exit", "logout"):
                break
            elif cmd == "help":
                print("help sysinfo pwd ls cd mkdir cat clear spwn exit")
            elif cmd == "sysinfo":
                print("SpawnOS | Python shell | Host OS:", os.name)
            elif cmd == "pwd":
                print(cwd)
            elif cmd == "ls":
                for p in sorted((cwd / args[0]).iterdir() if args else cwd.iterdir()):
                    print(p.name + ("/" if p.is_dir() else ""))
            elif cmd == "cd":
                target = (cwd / args[0]).expanduser().resolve() if args else Path.home()
                if target.is_dir():
                    cwd = target
                else:
                    print("Diretório não encontrado.")
            elif cmd == "mkdir":
                (cwd / args[0]).mkdir(parents=True, exist_ok=True)
            elif cmd == "cat":
                print((cwd / args[0]).read_text(encoding="utf-8"), end="")
            elif cmd == "clear":
                os.system("clear")
            elif cmd == "spwn":
                subprocess.run([str(ROOT / "bin/spawn"), *args], cwd=cwd)
            else:
                print("Comando desconhecido. Digite help.")
        except (EOFError, KeyboardInterrupt):
            print()
            break
        except Exception as e:
            print("SpawnOS:", e)

if __name__ == "__main__":
    main()
PY
fi

python - "$ROOT/lib/spawn/os_shell.py" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
if 'username=cfg.get("username"' not in s:
    s = s.replace(
        'name=cfg.get("name", "SpawnOS"),\n        session=SESSION,',
        'name=cfg.get("name", "SpawnOS"),\n        username=cfg.get("username", "User"),\n        session=SESSION,'
    )
p.write_text(s, encoding="utf-8")
PY

cat > "$BIN/spawnos" <<'SH2'
#!/usr/bin/env bash
set -e
SPWN_HOME="${SPWN_HOME:-$HOME/SPWN}"
export SPWN_HOME
exec python "$SPWN_HOME/lib/spawn/os_shell.py" "$@"
SH2
chmod +x "$BIN/spawnos"

cat > "$BIN/spawnos-setup" <<SH2
#!/usr/bin/env bash
exec bash "$ROOT/installers/install-spawnos.sh" --config
SH2
chmod +x "$BIN/spawnos-setup"

load_config() {
    mapfile -t V < <(python - "$CONFIG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for k in ("username", "prompt", "theme", "language", "startup", "color", "allow_external"):
    v = d.get(k, "")
    if isinstance(v, bool):
        v = str(v).lower()
    print(v)
PY
)
    USERNAME="${V[0]:-}"
    PROMPT="${V[1]:-{name}@{username}: \$ {cwd}}"
    THEME="${V[2]:-Crimson}"
    LANGUAGE="${V[3]:-Português}"
    STARTUP="${V[4]:-true}"
    COLOR="${V[5]:-true}"
    EXTERNAL="${V[6]:-true}"
}

save_config() {
    SPWN_USER="$USERNAME" \
    SPWN_PROMPT="$PROMPT" \
    SPWN_THEME="$THEME" \
    SPWN_LANGUAGE="$LANGUAGE" \
    SPWN_STARTUP="$STARTUP" \
    SPWN_COLOR="$COLOR" \
    SPWN_EXTERNAL="$EXTERNAL" \
    python - "$CONFIG" <<'PY'
import json, os, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    d = {}
d.update({
    "name": "SpawnOS",
    "username": os.environ["SPWN_USER"],
    "prompt": os.environ["SPWN_PROMPT"],
    "theme": os.environ["SPWN_THEME"],
    "language": os.environ["SPWN_LANGUAGE"],
    "startup": os.environ["SPWN_STARTUP"] == "true",
    "color": os.environ["SPWN_COLOR"] == "true",
    "allow_external": os.environ["SPWN_EXTERNAL"] == "true"
})
p.parent.mkdir(parents=True, exist_ok=True)
tmp = p.with_suffix(".tmp")
tmp.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
tmp.replace(p)
PY
}

draw_menu() {
    clear

    local accent="31"
    case "$THEME" in
        Crimson) accent="31" ;;
        Cyan) accent="36" ;;
        Mono) accent="37" ;;
    esac

    local title="SpawnOS Setup"
    local select_label="Select:"
    local username_label="Username"
    local prompt_label="Prompt"
    local theme_label="Theme"
    local language_label="Language"
    local startup_label="Startup"
    local components_label="Components"
    local save_label="Save and Exit"
    local navigation="↑/↓ Navigate   Enter Select   q Save and Exit"

    if [[ "$LANGUAGE" == "Português" ]]; then
        title="Configuração da SpawnOS"
        select_label="Selecionar:"
        username_label="Usuário"
        prompt_label="Prompt"
        theme_label="Tema"
        language_label="Idioma"
        startup_label="Inicialização"
        components_label="Componentes"
        save_label="Salvar e sair"
        navigation="↑/↓ Navegar   Enter Selecionar   q Salvar e sair"
    fi

    printf '\033[1;%sm' "$accent"
    printf '╭──────────────────────────────────────────────────────╮\n'
    printf '│ %-52s │\n' "$title"
    printf '╰──────────────────────────────────────────────────────╯\n'
    printf '\033[0m\n%s\n\n' "$select_label"

    local labels=(
        "$username_label"
        "$prompt_label"
        "$theme_label"
        "$language_label"
        "$startup_label"
        "$components_label"
        "$save_label"
    )

    local values=(
        "$USERNAME"
        "$PROMPT"
        "$THEME"
        "$LANGUAGE"
        "$STARTUP"
        "View"
        " "
    )

    local i
    for i in "${!labels[@]}"; do
        if (( i == SELECTED )); then
            printf '\033[1;%sm  ❯ [%d] %-18s %s\033[0m\n' \
                "$accent" "$((i+1))" "${labels[$i]}" "${values[$i]}"
        else
            printf '    [%d] %-18s %s\n' \
                "$((i+1))" "${labels[$i]}" "${values[$i]}"
        fi
    done

    printf '\n%s\n' "$navigation"
}
edit_item() {
    local value
    case "$SELECTED" in
        0)
            read -r -p "Disk Your Username: " value
            if [[ "$value" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
                USERNAME="$value"
                printf 'Defined!\n'
                sleep 0.5
            else
                printf 'Use 1-32 letras, números, _ ou -.\n'
                sleep 1
            fi
            ;;
        1)
            printf 'Placeholders: {name} {username} {cwd} {session}\n'
            read -r -p "Prompt: " value
            [[ -n "$value" ]] && PROMPT="$value"
            ;;
        2)
            case "$THEME" in
                Crimson) THEME="Cyan" ;;
                Cyan) THEME="Mono" ;;
                *) THEME="Crimson" ;;
            esac
            ;;
        3)
            if [[ "$LANGUAGE" == "Português" ]]; then
                LANGUAGE="English"
            else
                LANGUAGE="Português"
            fi
            ;;
        4)
            [[ "$STARTUP" == "true" ]] && STARTUP="false" || STARTUP="true"
            ;;
        5)
            clear
            printf 'SpawnOS Components\n\n'
            for d in "$ROOT/bin" "$ROOT/backend" "$ROOT/lib/spawn" "$ROOT/Def" "$ROOT/Funcs" "$ROOT/data"; do
                [[ -d "$d" ]] && printf '  [OK] %s\n' "$d" || printf '  [--] %s\n' "$d"
            done
            read -r -p "Enter para voltar..."
            ;;
        6)
            if [[ -z "$USERNAME" ]]; then
                read -r -p "Disk Your Username: " value
                if [[ "$value" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
                    USERNAME="$value"
                else
                    printf 'Username inválido.\n'
                    sleep 1
                    return
                fi
            fi
            save_config
            clear
            printf 'Defined!\n\n'
            printf 'SpawnOS@%s: $ ~\n' "$USERNAME"
            printf '\nConfiguration saved.\n'
            exit 0
            ;;
    esac
}

SELECTED=0
load_config

if [[ "${1:-}" != "--config" && -t 0 && -z "$USERNAME" ]]; then
    clear
    printf 'Disk Your Username: '
    read -r USERNAME
    [[ "$USERNAME" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || {
        printf 'Username inválido.\n'
        exit 1
    }
    save_config
fi

if [[ ! -t 0 ]]; then
    printf 'Este configurador precisa de um terminal interativo.\n'
    printf 'Execute: spawnos-setup\n'
    exit 1
fi

while true; do
    draw_menu
    IFS= read -rsn1 key || break
    case "$key" in
        $'\x1b')
            IFS= read -rsn2 -t 0.1 key || true
            case "$key" in
                '[A') (( SELECTED > 0 )) && ((SELECTED-=1)) ;;
                '[B') (( SELECTED < 6 )) && ((SELECTED+=1)) ;;
            esac
            ;;
        '')
            edit_item
            ;;
        q|Q)
            save_config
            break
            ;;
        1) SELECTED=0; edit_item ;;
        2) SELECTED=1; edit_item ;;
        3) SELECTED=2; edit_item ;;
        4) SELECTED=3; edit_item ;;
        5) SELECTED=4; edit_item ;;
        6) SELECTED=5; edit_item ;;
        7) SELECTED=6; edit_item ;;
    esac
done

printf 'Setup concluído. Execute: spawnos\n'
