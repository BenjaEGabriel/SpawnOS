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

# ---------- Gera ~/.bashrc do SpawnOS ----------
echo "Gerando ~/.bashrc (SpawnOS)..."

BASHRC_TARGET="${HOME}/.bashrc"

# Backup se já existir e não for nosso
if [[ -f "$BASHRC_TARGET" ]] && ! grep -q 'SpawnOS Shell' "$BASHRC_TARGET" 2>/dev/null; then
    cp -f "$BASHRC_TARGET" "${BASHRC_TARGET}.bak.$(date +%s)" 2>/dev/null || true
    echo "  Backup do .bashrc antigo salvo."
fi

# Se o .bashrc do projeto estiver no diretório atual, copia; senão gera embutido
if [[ -f ./.bashrc ]]; then
    cp -f ./.bashrc "$BASHRC_TARGET"
elif [[ -f ./SpawnOS/.bashrc ]]; then
    cp -f ./SpawnOS/.bashrc "$BASHRC_TARGET"
else
    cat > "$BASHRC_TARGET" << 'BASHRC'
# ==========================================
#             SpawnOS Shell
#        Custom Bash Environment
# ==========================================

# Cores ANSI (só para prompt)
_SPAWN_WHITE='\[\033[1;37m\]'
_SPAWN_GRAY='\[\033[1;90m\]'
_SPAWN_RESET='\[\033[0m\]'

# Prompt multilinha:
#   SpawnOS@session: /diretorio
#   |
#   --⟩
_spawn_prompt() {
    local dir="${PWD/#$HOME/~}"
    local session="${SPAWN_SESSION:-session}"
    PS1="${_SPAWN_WHITE}Spawn${_SPAWN_GRAY}OS${_SPAWN_RESET}@${session}: ${dir}"$'\n'
    PS1+="${_SPAWN_GRAY}|${_SPAWN_RESET}"$'\n'
    PS1+="${_SPAWN_GRAY}--⟩${_SPAWN_RESET} "
}

PROMPT_COMMAND=_spawn_prompt

# Histórico inteligente
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
shopt -s checkwinsize
shopt -s cmdhist

# Aliases úteis
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias cls='clear'
alias h='history'
alias ports='ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null'
alias myip='hostname -I 2>/dev/null || ip -4 addr show 2>/dev/null | awk "/inet /{print \$2}" | head -1'

# Navegação
mkcd() {
    mkdir -p -- "$1" && cd -- "$1"
}

# Pesquisa no histórico com grep
hg() {
    history | grep --color=auto -i -- "$@"
}

# Cores para ls
if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b 2>/dev/null)" || true
fi

# Restaura cores após comandos interrompidos
trap 'printf "\033[0m"' DEBUG

# PATH do SPWN / SpawnOS (se existir)
if [[ -n "${SPWN_HOME:-}" && -d "$SPWN_HOME/bin" ]]; then
    case ":$PATH:" in
        *":$SPWN_HOME/bin:"*) ;;
        *) export PATH="$SPWN_HOME/bin:$PATH" ;;
    esac
elif [[ -d "$HOME/SPWN/bin" ]]; then
    case ":$PATH:" in
        *":$HOME/SPWN/bin:"*) ;;
        *) export PATH="$HOME/SPWN/bin:$PATH" ;;
    esac
fi

# Mensagem de inicialização (banner) — só em shell interativo
if [[ $- == *i* ]]; then
    printf '%s\n' "
                       .:                             :.
                        -=                            +
                         :+*=-.                      .*.
                            -+***:                    +*.
                               -***-                  -*+.
                                 +**+                 :**-
                                 :***+.          :    .+*-
                             +. .+*****.       -*-    =**=
                            .*- =******=    .+*= .:+****+.
                            -*: =  -***+.   +* :+=+*****=
             .....          .*= .  =****:  +*-     *****
 .     .=+***********++:     :**++***. ..  +***++*****=                   =+:
   :-==-::.     .-*******+:   :******     .*****=:.+*:                  -*:
                  =*********-   -****+.   =***+.  ::    :=+*+=---      =*-
              ...  +*.  **+  :   .************+      :**+:           .**=
                :*= -=. .**=     :*************-  .=****..  -**+:. .+**=
                 .+*+.  **************.   .+*************=  -********+
                    :+*************=         -******=...-*********+:
                             -****+           -****.  .:-+***+-:.
                    ::-:-:    -***+           :****.
              .-*******-     :*****:          *********+=:..
           .*************************       :****************+.
         .+*********:   .*******+***************:. .:***- =: :*=
        -**=.     .:+=:. +**=.    -************-      =*=  :*: :--.
       :**-      -++=-=**+-    .  :****=..-*****.  .=-+***+**+.
      .*+      ..    .      :+:  :****-     -****=.  .+********.       .::::
     :+=                   =**********.  .  :******:    .+*************+=.   ..
  .=-.                   .*****.   =**.  +-:**-   +*:         :+++=-.
                         +****-  = -*-   +***-  .- *-
                        -*******- :*+    .****++*::*:
                       .***+:   =*=.      +*****-  +.
                       :**=     -         .****=    .
                       .**-                 +**=
                        ***                  =***-
                         +*:                   :***+-
                         .*=                      .:=*+:
                          -=                           -=
                          =.                            ..




       ____                              ___  ____
      / ___| _ __   __ ___      ___ __  / _ \/ ___|
      \___ \| '_ \ / _\` \ \ /\ / / '_ \| | | \___ \\
       ___) | |_) | (_| |\ V  V /| | | | |_| |___) |
      |____/| .__/ \__,_| \_/\_/ |_| |_|\___/|____/
            |_|
"
fi
BASHRC
fi

echo "  ~/.bashrc instalado."

# Reload shell config if present
if [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.bashrc" 2>/dev/null || true
elif [[ -f "$HOME/.profile" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.profile" 2>/dev/null || true
fi

echo "[OK] Instalação finalizada. Digite: spawnos"
echo "     Novo prompt: SpawnOS@session: ~"
echo "                  |"
echo "                  --⟩"
