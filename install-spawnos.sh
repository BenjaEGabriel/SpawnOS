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
            # Prefer a working interpreter that can at least import json + pathlib
            if "$c" -c "import json, sys; sys.exit(0 if sys.version_info[0] >= 2 else 1)" 2>/dev/null; then
                echo "$c"
                return 0
            fi
        fi
    done
    return 1
}

PYTHON="$(detect_python || true)"
if [[ -z "${PYTHON:-}" ]]; then
    printf 'Nenhum interpretador Python encontrado (python3.x / python / python2).\n'
    printf 'Instale Python e execute novamente.\n'
    exit 1
fi

# Warn if only Python 2 is available (many features will be limited)
if "$PYTHON" -c "import sys; sys.exit(0 if sys.version_info[0] < 3 else 1)" 2>/dev/null; then
    printf '\033[33mAviso: Python 2 detectado (%s). Algumas funções modernas podem falhar.\033[0m\n' "$PYTHON"
fi

printf 'Usando: %s (%s)\n' "$PYTHON" "$("$PYTHON" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?')"

ROOT="${SPWN_HOME:-$HOME/SPWN}"
OS="$ROOT/SpawnOS"
BIN="$ROOT/bin"
ETC="$ROOT/etc"
CONFIG="$ETC/spawnos.json"
SELF="${BASH_SOURCE[0]}"

mkdir -p "$OS/home" "$OS/apps" "$OS/tmp" "$BIN" "$ETC" "$ROOT/logs" "$ROOT/lib/spawn" "$ROOT/installers"

if [[ ! -f "$CONFIG" ]]; then
    ROOT_PATH="$ROOT" "$PYTHON" - <<'PY'
import json, os, sys
try:
    from pathlib import Path
except ImportError:
    # Python 2 fallback
    class Path(object):
        def __init__(self, p): self._p = p
        def __truediv__(self, o): return Path(self._p + "/" + str(o))
        def write_text(self, data, encoding="utf-8"):
            with open(self._p, "w") as f: f.write(data)
        def parent(self): return Path("/".join(self._p.split("/")[:-1]) or ".")
p = Path(os.environ["ROOT_PATH"]) / "etc/spawnos.json"
try:
    p.parent.mkdir(parents=True, exist_ok=True)
except Exception:
    import os as _os
    _os.makedirs(str(p.parent._p if hasattr(p.parent, "_p") else p.parent), exist_ok=True)
data = {
    "name": "SpawnOS",
    "username": "",
    "prompt": "{name}@{username}: $ {cwd}",
    "theme": "Crimson",
    "language": "Português",
    "startup": True,
    "color": True,
    "allow_external": True
}
text = json.dumps(data, indent=2)
if hasattr(p, "write_text"):
    p.write_text(text, encoding="utf-8")
else:
    with open(str(p), "w") as f:
        f.write(text)
PY
fi

if [[ ! -f "$OS/installed" ]]; then
    printf 'SpawnOS 0.1.0-beta\n' > "$OS/installed"
fi

if [[ ! -f "$ROOT/lib/spawn/os_shell.py" ]]; then
    cat > "$ROOT/lib/spawn/os_shell.py" <<'PY'
# -*- coding: utf-8 -*-
from __future__ import print_function
import json, os, sys

try:
    from pathlib import Path
except ImportError:
    class Path(object):
        def __init__(self, p): self._p = str(p)
        def __str__(self): return self._p
        def __truediv__(self, o): return Path(self._p.rstrip("/") + "/" + str(o))
        def expanduser(self): return Path(os.path.expanduser(self._p))
        def resolve(self): return Path(os.path.abspath(self._p))
        def is_dir(self): return os.path.isdir(self._p)
        def iterdir(self):
            for n in sorted(os.listdir(self._p)):
                yield Path(self._p + "/" + n)
        def mkdir(self, parents=False, exist_ok=False):
            if parents:
                try: os.makedirs(self._p)
                except OSError: pass
            else:
                os.mkdir(self._p)
        def read_text(self, encoding="utf-8"):
            with open(self._p, "r") as f: return f.read()
        def write_text(self, data, encoding="utf-8"):
            with open(self._p, "w") as f: f.write(data)
        @property
        def name(self): return os.path.basename(self._p)
        @property
        def home(self): return Path(os.path.expanduser("~"))
        def cwd(self): return Path(os.getcwd())

try:
    import shlex
except ImportError:
    import pipes as shlex  # Py2

try:
    import subprocess
except ImportError:
    subprocess = None

ROOT = Path(os.environ.get("SPWN_HOME", str(Path.home() / "SPWN") if hasattr(Path, "home") else os.path.expanduser("~/SPWN")))
CONFIG = ROOT / "etc/spawnos.json"

def _load_cfg():
    try:
        with open(str(CONFIG), "r") as f:
            return json.load(f)
    except Exception:
        return {"name": "SpawnOS", "username": "User", "prompt": "{name}@{username}: $ {cwd}"}

cfg = _load_cfg()
cwd = Path(os.getcwd())

def prompt():
    try:
        return cfg["prompt"].format(
            name=cfg.get("name", "SpawnOS"),
            username=cfg.get("username", "User"),
            cwd=str(cwd),
            session="LOCAL"
        )
    except Exception:
        return "SpawnOS> "

def main():
    global cwd
    print("SpawnOS 0.1.0-beta")
    while True:
        try:
            try:
                line = raw_input(prompt())  # Py2
            except NameError:
                line = input(prompt())      # Py3
            try:
                a = shlex.split(line)
            except Exception:
                a = line.split()
            if not a:
                continue
            cmd = a[0]
            args = a[1:]
            if cmd in ("exit", "logout"):
                break
            elif cmd == "help":
                print("help sysinfo pwd ls cd mkdir cat clear spwn exit")
            elif cmd == "sysinfo":
                print("SpawnOS | Python shell | Host OS:", os.name)
            elif cmd == "pwd":
                print(cwd)
            elif cmd == "ls":
                try:
                    target = (cwd / args[0]) if args else cwd
                    for p in sorted(target.iterdir() if hasattr(target, "iterdir") else [Path(os.path.join(str(target), n)) for n in os.listdir(str(target))]):
                        name = p.name if hasattr(p, "name") else os.path.basename(str(p))
                        isdir = p.is_dir() if hasattr(p, "is_dir") else os.path.isdir(str(p))
                        print(name + ("/" if isdir else ""))
                except Exception as e:
                    print("ls:", e)
            elif cmd == "cd":
                try:
                    if args:
                        target = (cwd / args[0]).expanduser().resolve()
                    else:
                        target = Path.home() if hasattr(Path, "home") else Path(os.path.expanduser("~"))
                    if target.is_dir():
                        cwd = target
                        os.chdir(str(cwd))
                    else:
                        print("Diretório não encontrado.")
                except Exception as e:
                    print("cd:", e)
            elif cmd == "mkdir":
                try:
                    (cwd / args[0]).mkdir(parents=True, exist_ok=True)
                except Exception as e:
                    print("mkdir:", e)
            elif cmd == "cat":
                try:
                    print((cwd / args[0]).read_text(encoding="utf-8"), end="")
                except Exception as e:
                    print("cat:", e)
            elif cmd == "clear":
                os.system("clear")
            elif cmd == "spwn":
                spawn_bin = str(ROOT / "bin/spawn")
                if subprocess:
                    subprocess.call([spawn_bin] + list(args), cwd=str(cwd))
                else:
                    os.system(spawn_bin + " " + " ".join(args))
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

# Soft patch for older shells that may miss username in prompt format
"$PYTHON" - "$ROOT/lib/spawn/os_shell.py" <<'PY' || true
import sys
try:
    from pathlib import Path
except ImportError:
    class Path(object):
        def __init__(self, p): self._p = p
        def read_text(self, encoding="utf-8"):
            with open(self._p) as f: return f.read()
        def write_text(self, data, encoding="utf-8"):
            with open(self._p, "w") as f: f.write(data)
p = Path(sys.argv[1])
try:
    s = p.read_text(encoding="utf-8")
except TypeError:
    s = p.read_text()
if 'username=cfg.get("username"' not in s and "username=cfg.get('username'" not in s:
    s = s.replace(
        'name=cfg.get("name", "SpawnOS"),\n        session=SESSION,',
        'name=cfg.get("name", "SpawnOS"),\n        username=cfg.get("username", "User"),\n        session=SESSION,'
    )
    try:
        p.write_text(s, encoding="utf-8")
    except TypeError:
        p.write_text(s)
PY

cat > "$BIN/spawnos" <<SH2
#!/usr/bin/env bash
set -e
SPWN_HOME="\${SPWN_HOME:-\$HOME/SPWN}"
export SPWN_HOME
# Re-detect Python at runtime
_py() {
    for c in python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8 python3 python python2.7 python2; do
        command -v "\$c" >/dev/null 2>&1 && echo "\$c" && return
    done
    echo python
}
exec "\$(_py)" "\$SPWN_HOME/lib/spawn/os_shell.py" "\$@"
SH2
chmod +x "$BIN/spawnos"

# Keep a copy of this installer
mkdir -p "$ROOT/installers"
cp -f "$SELF" "$ROOT/installers/install-spawnos.sh" 2>/dev/null || true

cat > "$BIN/spawnos-setup" <<SH2
#!/usr/bin/env bash
exec bash "\$ROOT/installers/install-spawnos.sh" --config
SH2
# Fix the variable expansion above
cat > "$BIN/spawnos-setup" <<SH2
#!/usr/bin/env bash
SPWN_HOME="\${SPWN_HOME:-\$HOME/SPWN}"
exec bash "\$SPWN_HOME/installers/install-spawnos.sh" --config
SH2
chmod +x "$BIN/spawnos-setup"

load_config() {
    mapfile -t V < <("$PYTHON" - "$CONFIG" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except TypeError:
    d = json.load(open(sys.argv[1]))
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
    "$PYTHON" - "$CONFIG" <<'PY'
import json, os, sys
try:
    from pathlib import Path
except ImportError:
    class Path(object):
        def __init__(self, p): self._p = p
        def read_text(self, encoding="utf-8"):
            with open(self._p) as f: return f.read()
        def write_text(self, data, encoding="utf-8"):
            with open(self._p, "w") as f: f.write(data)
        @property
        def parent(self):
            import os
            return Path(os.path.dirname(self._p) or ".")
        def with_suffix(self, s):
            return Path(self._p + s)
        def replace(self, other):
            import os, shutil
            shutil.move(self._p, other._p if hasattr(other, "_p") else other)
        def mkdir(self, parents=True, exist_ok=True):
            import os
            try: os.makedirs(self._p)
            except: pass

p = Path(sys.argv[1])
try:
    d = json.loads(p.read_text(encoding="utf-8"))
except Exception:
    try:
        d = json.loads(p.read_text())
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
try:
    p.parent.mkdir(parents=True, exist_ok=True)
except Exception:
    import os
    os.makedirs(str(getattr(p.parent, "_p", p.parent)), exist_ok=True)
tmp = p.with_suffix(".tmp")
text = json.dumps(d, ensure_ascii=False, indent=2)
try:
    tmp.write_text(text, encoding="utf-8")
except TypeError:
    tmp.write_text(text)
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
