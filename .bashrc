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
