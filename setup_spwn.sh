#!/usr/bin/env bash
# Instalador SPWN — detecta Termux ou Linux e cria a árvore no local certo
set -e

# ---------- detecção de ambiente ----------
is_termux() {
    [[ -d /data/data/com.termux/files/usr ]] || [[ -n "${TERMUX_VERSION:-}" ]] || [[ "$(uname -o 2>/dev/null)" == "Android" && -d /data/data/com.termux ]]
}

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
            echo "$c"
            return 0
        fi
    done
    return 1
}

if is_termux; then
    ENV_NAME="Termux"
    DEFAULT_HOME="/data/data/com.termux/files/spwn"
    # No Termux o PREFIX costuma ser /data/data/com.termux/files/usr
    BIN_LINK_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    PKG_INSTALL="pkg install -y"
else
    ENV_NAME="Linux"
    DEFAULT_HOME="${HOME}/SPWN"
    BIN_LINK_DIR="${PREFIX:-/usr/local}/bin"
    # tenta apt/dnf/pacman só se precisar de python depois
    PKG_INSTALL=""
fi

SPWN_HOME="${SPWN_HOME:-$DEFAULT_HOME}"
export SPWN_HOME

echo "Ambiente detectado: $ENV_NAME"
echo "SPWN_HOME: $SPWN_HOME"

PYTHON="$(detect_python || true)"
if [[ -z "${PYTHON:-}" ]]; then
    if is_termux; then
        echo "Instalando Python via pkg..."
        pkg install -y python || true
        PYTHON="$(detect_python || true)"
    else
        echo "Python não encontrado. Instale python3 e rode novamente."
        exit 1
    fi
fi
if [[ -z "${PYTHON:-}" ]]; then
    echo "Nenhum interpretador Python disponível."
    exit 1
fi
echo "Usando Python: $PYTHON ($($PYTHON -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo '?'))"

mkdir -p "$SPWN_HOME"
mkdir -p "$SPWN_HOME/."
cat > "$SPWN_HOME/README.md" <<'SPWN_EOF'
# Spawn (SPWN) 0.1

Linguagem reativa (Termux e Linux): um programa descreve **classes** (regras) que reagem a uma
**resposta** (`response`) vinda de `-r`, do stdin ou do `repl`.

## Sintaxe

Arquivos usam a extensão **`.spw`** (`.spwn` continua aceita). Pode omitir a extensão: `spwn ola -r oi`.
Uma 1ª linha `#!/usr/bin/env spwn` torna o arquivo executável (`chmod +x`), pois `#` é comentário.

```spwn
<spwn>
spwn "print" == ("Iniciando")                       # chamadas soltas: só antes da 1ª regra

spawn-def_class == ("print") if
      response-is("oi") spwn "print" == ("Olá")     # regra: condição + ações

spawn-def_class == ("x") if response-has("a") and not response-has("b")
      spwn "print" == ("achei {response}")
else
      spwn "print" == ("não achei")
</spwn>
```

- Toda chamada que segue uma regra pertence a ela até o próximo `spawn-def_class` ou `</spwn>`.
- Todas as regras são avaliadas, em ordem (não para na primeira que casa).
- `#` comenta até o fim da linha. Escapes: `\n \t \" \\`. `{response}` é substituído pela resposta.

**Condições:** `response-is("t")`, `response-has("t")`, `response-starts("t")`, `response-any()`;
combine com `and`, `or`, `not` e parênteses. Por padrão ignora maiúsculas (perfil `strict` não ignora).

**Ações** (`spwn "ação" == (args)`):

| ação | efeito | transpila? |
|---|---|---|
| `print(a, ...)` / `write(a, ...)` | imprime com / sem quebra de linha | sim |
| `run("cmd")` | executa no shell; a resposta vai em `$SPWN_RESPONSE` | sim |
| `exit("0".."255")` | encerra | sim |
| `save(chave, valor)` / `load(chave)` | persistência em `files/data/store.json` | só interpretador |
| `fwrite(arq, txt)` / `fappend` / `fread(arq)` | arquivos dentro de `files/data/` | só interpretador |

`run` **não aceita `{response}`** no comando (evita injeção); use `$SPWN_RESPONSE`.
`fwrite/fread` não saem de `files/data/` (bloqueia `../` e symlinks).

## CLI

```
spwn arquivo.spw -r "oi"        # interpreta (atalho de `spwn run`)
spwn repl arquivo.spw           # cada linha digitada é uma resposta; "sair" encerra
spwn check arquivo.spw          # só valida
spwn build arquivo.spw -t bash -o saida.sh    # python | node | php | bash
spwn exec  arquivo.spw -t node -r "oi"        # transpila e roda
```
Programas gerados recebem a resposta em `argv[1]` ou na 1ª linha do stdin.
Perfis (`-p` ou `SPWN_PROFILE`): `default`, `strict`, `chat`, `safe` (desliga `run`).
Dados: `SPWN_DATA_DIR`. Códigos de saída: 0 ok, 2 erro SPWN, ou o valor de `exit`.

## Estrutura

```
spwn/
├── bin/spwn          CLI
├── backend/          lexer, parser, nodes, interpreter, transpiler, cli, errors
├── settings/         spwn.json, profiles.json, env.sh, config.py
├── files/            fileio.py (sandbox), store.py (JSON atômico)
├── strings/          keywords.py, tokens.py, strutil.py
├── examples/  tests/
```

Testes: `python3 tests/test_spwn.py` (alvos sem runtime instalado são pulados).
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/__init__.py" <<'SPWN_EOF'
"""Motor da SPWN: lexer, parser, interpretador e transpilador."""
VERSION = "0.1.0"
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/cli.py" <<'SPWN_EOF'
"""CLI da SPWN: run, repl, build, exec, check, version."""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from backend import VERSION
from backend.errors import SpwnError, SpwnTranspileError
from backend.interpreter import Interpreter
from backend.parser import parse
from backend.transpiler import EXT, canonical, transpile
from settings import config
from strings.keywords import EXTENSIONS

COMMANDS = {"run", "repl", "build", "exec", "check", "version"}
RUNTIMES = {"python": ["python3", "python"], "node": ["node"], "php": ["php"], "bash": ["bash"]}


def resolve_source(path):
    """Acha o arquivo: aceita o nome exato ou sem extensão (tenta .spw e depois .spwn)."""
    if os.path.isfile(path):
        return path
    if not path.lower().endswith(EXTENSIONS):
        for ext in EXTENSIONS:
            if os.path.isfile(path + ext):
                return path + ext
    tried = path if path.lower().endswith(EXTENSIONS) else " / ".join(path + e for e in EXTENSIONS)
    raise SpwnError(f"arquivo não encontrado: {tried}")


def _load(path, profile):
    path = resolve_source(path)
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
    except OSError as e:
        raise SpwnError(f"não foi possível ler {path}: {e.strerror}")
    return config.load(profile), parse(src)


def _ask(cfg):
    if sys.stdin.isatty():
        sys.stderr.write(cfg.repl_prompt)
        sys.stderr.flush()
    return sys.stdin.readline()


def cmd_run(a):
    cfg, prog = _load(a.file, a.profile)
    if a.response is not None:
        resp = a.response
    else:
        resp = _ask(cfg) if prog.rules else ""   # sem classes não há o que reagir
    return Interpreter(cfg).run(prog, resp)


def cmd_repl(a):
    cfg, prog = _load(a.file, a.profile)
    it = Interpreter(cfg)
    while True:
        try:
            line = input(cfg.repl_prompt)
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if line.strip().lower() in cfg.exit_words:
            return 0
        code = it.run(prog, line)
        if it.exited:
            return code


def cmd_check(a):
    _, prog = _load(a.file, a.profile)
    n = sum(len(r.then) + len(r.otherwise) for r in prog.rules)
    print(f"OK: {len(prog.rules)} classe(s), {n} ação(ões) em regras, "
          f"{len(prog.setup)} chamada(s) iniciais")
    return 0


def cmd_build(a):
    cfg, prog = _load(a.file, a.profile)
    target = canonical(a.target or cfg.default_target)
    code = transpile(prog, target, cfg)
    if a.output and a.output != "-":
        with open(a.output, "w", encoding="utf-8") as f:
            f.write(code)
        os.chmod(a.output, 0o755)
        print(f"gerado: {a.output} ({target})", file=sys.stderr)
    else:
        sys.stdout.write(code)
    return 0


def cmd_exec(a):
    cfg, prog = _load(a.file, a.profile)
    target = canonical(a.target or cfg.default_target)
    code = transpile(prog, target, cfg)
    exe = next((p for p in map(shutil.which, RUNTIMES[target]) if p), None)
    if not exe:
        raise SpwnTranspileError(f"{RUNTIMES[target][0]} não encontrado (instale: {RUNTIMES[target][0]})")
    with tempfile.NamedTemporaryFile("w", suffix=EXT[target], delete=False, encoding="utf-8") as tmp:
        tmp.write(code)
    try:
        cmd = [exe, tmp.name] + ([a.response] if a.response is not None else [])
        return subprocess.call(cmd)
    finally:
        os.unlink(tmp.name)


def cmd_version(_a):
    print(f"spwn {VERSION}")
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="spwn", description="SPWN — linguagem reativa para Termux")
    p.add_argument("--version", action="version", version=f"spwn {VERSION}")
    sub = p.add_subparsers(dest="cmd")

    def add(name, fn, help_, target=False, response=False):
        s = sub.add_parser(name, help=help_)
        s.set_defaults(fn=fn)
        if name != "version":
            s.add_argument("file", help="arquivo .spw (ou .spwn); a extensão pode ser omitida")
            s.add_argument("-p", "--profile", help="perfil de settings/profiles.json")
        if target:
            s.add_argument("-t", "--target", help="python | node | php | bash")
        if response:
            s.add_argument("-r", "--response", help="resposta a reagir (senão lê do stdin)")
        return s

    add("run", cmd_run, "interpreta o arquivo", response=True)
    add("repl", cmd_repl, "loop interativo: cada linha vira uma resposta")
    add("check", cmd_check, "valida a sintaxe")
    b = add("build", cmd_build, "transpila para outra linguagem", target=True)
    b.add_argument("-o", "--output", help="arquivo de saída (padrão: stdout)")
    add("exec", cmd_exec, "transpila e executa no runtime do alvo", target=True, response=True)
    add("version", cmd_version, "mostra a versão")
    return p


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] not in COMMANDS and not argv[0].startswith("-"):
        argv.insert(0, "run")          # `spwn arquivo.spw` == `spwn run arquivo.spw`
    p = build_parser()
    a = p.parse_args(argv)
    if not getattr(a, "fn", None):
        p.print_help()
        return 1
    try:
        return a.fn(a) or 0
    except SpwnError as e:
        sys.stderr.write(f"spwn: erro: {e}\n")
        return 2
    except KeyboardInterrupt:
        return 130
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/errors.py" <<'SPWN_EOF'
class SpwnError(Exception):
    def __init__(self, msg, line=None, col=None):
        self.msg, self.line, self.col = msg, line, col
        super().__init__(msg)

    def __str__(self):
        if self.line is None:
            return self.msg
        col = f", coluna {self.col}" if self.col else ""
        return f"{self.msg} (linha {self.line}{col})"


class SpwnSyntaxError(SpwnError):
    pass


class SpwnRuntimeError(SpwnError):
    pass


class SpwnTranspileError(SpwnError):
    pass
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/interpreter.py" <<'SPWN_EOF'
"""Interpretador SPWN: executa o programa reagindo a uma 'response'."""
import os
import shutil
import subprocess
import sys

from backend.errors import SpwnRuntimeError
from backend.nodes import Atom, BoolOp, Not
from files.fileio import Sandbox
from files.store import Store
from strings.strutil import interpolate


class _Exit(Exception):
    def __init__(self, code):
        self.code = code


class Interpreter:
    def __init__(self, cfg, out=None):
        self.cfg = cfg
        self.out = sys.stdout if out is None else out
        self.store = Store(cfg.data_dir)
        self.box = Sandbox(cfg.data_dir)
        self.exited = False

    def run(self, prog, response):
        response = response.strip()
        self.exited = False
        try:
            for a in prog.setup:
                self._act(a, response)
            for r in prog.rules:
                if r.cond is None or self._cond(r.cond, response):
                    acts = r.then
                else:
                    acts = r.otherwise
                for a in acts:
                    self._act(a, response)
        except _Exit as e:
            self.exited = True
            self.out.flush()
            return e.code
        self.out.flush()
        return 0

    # ---- condições ----
    def _norm(self, s):
        return s if self.cfg.case_sensitive else s.lower()

    def _cond(self, c, resp):
        if isinstance(c, Atom):
            r, a = self._norm(resp), self._norm(c.arg or "")
            if c.kind == "is":
                return r == a
            if c.kind == "has":
                return a in r
            if c.kind == "starts":
                return r.startswith(a)
            return True
        if isinstance(c, Not):
            return not self._cond(c.item, resp)
        if c.op == "and":
            return all(self._cond(x, resp) for x in c.items)
        return any(self._cond(x, resp) for x in c.items)

    # ---- ações ----
    def _act(self, a, resp):
        try:
            if a.cls == "run":
                return self._shell(a.args[0], resp)
            args = [interpolate(x, resp) for x in a.args]
            if a.cls == "print":
                self.out.write(" ".join(args) + "\n")
            elif a.cls == "write":
                self.out.write(" ".join(args))
            elif a.cls == "exit":
                raise _Exit(int(args[0]) if args else 0)
            elif a.cls == "save":
                self.store.set(args[0], args[1])
            elif a.cls == "load":
                self.out.write(str(self.store.get(args[0])) + "\n")
            elif a.cls == "fwrite":
                self.box.write(args[0], args[1])
            elif a.cls == "fappend":
                self.box.append(args[0], args[1])
            elif a.cls == "fread":
                self.out.write(self.box.read(args[0]))
        except SpwnRuntimeError as e:
            if e.line is None:
                e.line = a.line
            raise

    def _shell(self, cmd, resp):
        if not self.cfg.allow_run:
            raise SpwnRuntimeError("ação 'run' desabilitada neste perfil")
        self.out.flush()
        env = dict(os.environ, SPWN_RESPONSE=resp)   # resposta vai por ambiente, nunca no comando
        try:
            subprocess.run(cmd, shell=True, executable=shutil.which("sh"),
                           env=env, timeout=self.cfg.shell_timeout)
        except subprocess.TimeoutExpired:
            raise SpwnRuntimeError(f"comando excedeu {self.cfg.shell_timeout:g}s: {cmd!r}")
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/lexer.py" <<'SPWN_EOF'
"""Lexer da SPWN."""
from backend.errors import SpwnSyntaxError
from strings.strutil import unescape
from strings.tokens import MASTER, Token, T


def tokenize(src):
    pos, line, col, out = 0, 1, 1, []
    n = len(src)
    while pos < n:
        m = MASTER.match(src, pos)
        if not m:
            ch = src[pos]
            msg = "string não terminada" if ch == '"' else f"caractere inesperado {ch!r}"
            raise SpwnSyntaxError(msg, line, col)
        kind, text = m.lastgroup, m.group()
        if kind not in ("WS", "COMMENT"):
            value = unescape(text[1:-1]) if kind == T.STRING else text
            out.append(Token(kind, value, line, col))
        nl = text.count("\n")
        if nl:
            line += nl
            col = len(text) - text.rfind("\n")
        else:
            col += len(text)
        pos = m.end()
    out.append(Token(T.EOF, "", line, col))
    return out
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/nodes.py" <<'SPWN_EOF'
"""Nós da AST da SPWN."""
from dataclasses import dataclass, field
from typing import List, Optional, Union


@dataclass
class Atom:
    kind: str                 # is | has | starts | any
    arg: Optional[str] = None


@dataclass
class Not:
    item: "Cond"


@dataclass
class BoolOp:
    op: str                   # and | or
    items: List["Cond"]


Cond = Union[Atom, Not, BoolOp]


@dataclass
class Action:
    cls: str
    args: List[str]
    line: int = 0


@dataclass
class Rule:
    name: str
    cond: Optional[Cond]
    then: List[Action] = field(default_factory=list)
    otherwise: List[Action] = field(default_factory=list)
    line: int = 0


@dataclass
class Program:
    setup: List[Action] = field(default_factory=list)
    rules: List[Rule] = field(default_factory=list)
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/parser.py" <<'SPWN_EOF'
"""Parser (descida recursiva) e validação semântica da SPWN.

Gramática:
    programa := ( "<spwn>" bloco "</spwn>" )*
    bloco    := ( chamada | regra )*          # chamadas soltas só antes da 1ª regra
    regra    := "spawn-def_class" "==" "(" STRING ")" [ "if" cond ]
                chamada* [ "else" chamada* ]
    chamada  := "spwn" STRING "==" "(" [ STRING ("," STRING)* ] ")"
    cond     := e ("or" e)* ;  e := nao ("and" nao)* ;  nao := "not" nao | atomo
    atomo    := "response-is" "(" STRING ")" | ... | "(" cond ")"
"""
import re

from backend.errors import SpwnSyntaxError
from backend.lexer import tokenize
from backend.nodes import Action, Atom, BoolOp, Not, Program, Rule
from strings.keywords import (ACTIONS, CONDITIONS, KW_AND, KW_CALL, KW_DEF,
                              KW_ELSE, KW_IF, KW_NOT, KW_OR, INTERP_VAR)
from strings.tokens import T

_NAME_RE = re.compile(r"^[\w .\-]{1,64}$")
_INT_RE = re.compile(r"[0-9]{1,3}")


class Parser:
    def __init__(self, tokens):
        self.toks, self.i = tokens, 0

    @property
    def cur(self):
        return self.toks[self.i]

    def advance(self):
        t = self.cur
        if t.kind != T.EOF:
            self.i += 1
        return t

    def err(self, msg, tok=None):
        tok = tok or self.cur
        raise SpwnSyntaxError(msg, tok.line, tok.col)

    def expect(self, kind, value=None):
        t = self.cur
        if t.kind != kind or (value is not None and t.value != value):
            self.err(f"esperado {value or kind!r}, encontrado {t.value or t.kind!r}")
        return self.advance()

    def is_kw(self, word):
        return self.cur.kind == T.IDENT and self.cur.value == word

    # ---- estrutura ----
    def parse(self):
        prog = Program()
        while self.cur.kind != T.EOF:
            self.expect(T.TAG_OPEN)
            self.block(prog)
        return prog

    def block(self, prog):
        while True:
            if self.cur.kind == T.TAG_CLOSE:
                self.advance()
                return
            if self.cur.kind == T.EOF:
                self.err("bloco <spwn> não foi fechado com </spwn>")
            if self.is_kw(KW_DEF):
                prog.rules.append(self.rule())
            elif self.is_kw(KW_CALL):
                prog.setup.append(self.action())
            else:
                self.err(f"instrução inesperada {self.cur.value!r}")

    def rule(self):
        head = self.expect(T.IDENT, KW_DEF)
        self.expect(T.EQ)
        self.expect(T.LPAREN)
        name = self.expect(T.STRING).value
        self.expect(T.RPAREN)
        cond = None
        if self.is_kw(KW_IF):
            self.advance()
            cond = self.or_()
        rule = Rule(name, cond, [], [], head.line)
        target, seen_else = rule.then, False
        while True:
            if self.is_kw(KW_CALL):
                target.append(self.action())
            elif self.is_kw(KW_ELSE):
                if cond is None:
                    self.err("'else' exige um 'if' na regra")
                if seen_else:
                    self.err("'else' duplicado")
                seen_else = True
                self.advance()
                target = rule.otherwise
            else:
                return rule

    def action(self):
        head = self.expect(T.IDENT, KW_CALL)
        name = self.expect(T.STRING).value
        self.expect(T.EQ)
        self.expect(T.LPAREN)
        args = []
        if self.cur.kind == T.STRING:
            args.append(self.advance().value)
            while self.cur.kind == T.COMMA:
                self.advance()
                args.append(self.expect(T.STRING).value)
        self.expect(T.RPAREN)
        return Action(name, args, head.line)

    # ---- condições ----
    def or_(self):
        items = [self.and_()]
        while self.is_kw(KW_OR):
            self.advance()
            items.append(self.and_())
        return items[0] if len(items) == 1 else BoolOp("or", items)

    def and_(self):
        items = [self.not_()]
        while self.is_kw(KW_AND):
            self.advance()
            items.append(self.not_())
        return items[0] if len(items) == 1 else BoolOp("and", items)

    def not_(self):
        if self.is_kw(KW_NOT):
            self.advance()
            return Not(self.not_())
        return self.atom()

    def atom(self):
        t = self.cur
        if t.kind == T.LPAREN:
            self.advance()
            c = self.or_()
            self.expect(T.RPAREN)
            return c
        if t.kind == T.IDENT and t.value in CONDITIONS:
            kind, needs_arg = CONDITIONS[t.value]
            self.advance()
            self.expect(T.LPAREN)
            arg = self.expect(T.STRING).value if needs_arg else None
            self.expect(T.RPAREN)
            return Atom(kind, arg)
        self.err(f"condição desconhecida {t.value or t.kind!r}")


def _check_action(a):
    spec = ACTIONS.get(a.cls)
    if spec is None:
        raise SpwnSyntaxError(
            f"ação desconhecida {a.cls!r}. Disponíveis: {', '.join(sorted(ACTIONS))}", a.line)
    lo, hi, _ = spec
    if not lo <= len(a.args) <= hi:
        raise SpwnSyntaxError(f"ação {a.cls!r} espera de {lo} a {hi} argumento(s)", a.line)
    if a.cls == "run" and INTERP_VAR in a.args[0]:
        raise SpwnSyntaxError(
            "'run' não aceita {response} (risco de injeção de comando); "
            "use a variável de ambiente $SPWN_RESPONSE", a.line)
    if a.cls == "exit" and a.args:
        if not _INT_RE.fullmatch(a.args[0]) or int(a.args[0]) > 255:
            raise SpwnSyntaxError("'exit' espera um inteiro literal de 0 a 255", a.line)


def validate(prog):
    for a in prog.setup:
        _check_action(a)
    for r in prog.rules:
        if not _NAME_RE.match(r.name):
            raise SpwnSyntaxError(
                f"nome de classe inválido {r.name!r} (use letras, números, espaço, . _ -)", r.line)
        for a in r.then + r.otherwise:
            _check_action(a)
    return prog


def parse(src):
    return validate(Parser(tokenize(src)).parse())
SPWN_EOF
mkdir -p "$SPWN_HOME/backend"
cat > "$SPWN_HOME/backend/transpiler.py" <<'SPWN_EOF'
"""Transpilador SPWN -> Python / Node.js / PHP / Bash.

Os programas gerados recebem a resposta em argv[1] (ou na 1ª linha do stdin).
"""
import json

from backend.errors import SpwnTranspileError
from backend.nodes import Atom, Not
from strings.keywords import ACTIONS
from strings.strutil import join_args


class Emitter:
    ext = ""
    cm = "#"
    ind = "    "
    var = "response"
    and_, or_, not_ = " and ", " or ", "not "

    def __init__(self, cfg):
        self.cfg = cfg

    def lc(self, s):
        return s if self.cfg.case_sensitive else s.lower()

    def indent(self, lines):
        return [self.ind + l for l in lines]

    def wrap(self, x):
        return f"({x})"

    def expr(self, args):
        parts = join_args(args)
        if not parts:
            return self.q("")
        return self.cat([self.q(p[1]) if p[0] == "lit" else self.var for p in parts])

    def cond(self, c):
        if isinstance(c, Atom):
            return self.atom(c.kind, self.lc(c.arg or ""))
        if isinstance(c, Not):
            return self.not_ + self.wrap(self.cond(c.item))
        sep = self.and_ if c.op == "and" else self.or_
        return sep.join(self.wrap(self.cond(x)) for x in c.items)

    def rule(self, r):
        out = [f"{self.cm} classe: {r.name}"]
        then = [l for a in r.then for l in self.action(a)]
        other = [l for a in r.otherwise for l in self.action(a)]
        if r.cond is None:
            out += then
        else:
            out += self.branch(self.cond(r.cond), then, other)
        return out + [""]

    def emit(self, prog):
        out = self.header()
        for a in prog.setup:
            out += self.action(a)
        for r in prog.rules:
            out += self.rule(r)
        return "\n".join(out + self.footer()) + "\n"

    def footer(self):
        return []


class PyEmitter(Emitter):
    ext = ".py"

    def q(self, s):
        return json.dumps(s, ensure_ascii=False)

    def cat(self, xs):
        return " + ".join(xs)

    def header(self):
        low = "" if self.cfg.case_sensitive else ".lower()"
        return ["#!/usr/bin/env python3", "# Gerado por SPWN — não edite à mão.",
                "import os, subprocess, sys", "",
                "response = (sys.argv[1] if len(sys.argv) > 1 else sys.stdin.readline()).strip()",
                f"_r = response{low}", ""]

    def atom(self, k, a):
        q = self.q(a)
        return {"is": f"_r == {q}", "has": f"{q} in _r",
                "starts": f"_r.startswith({q})", "any": "True"}[k]

    def branch(self, cond, then, other):
        out = [f"if {cond}:"] + self.indent(then or ["pass"])
        if other:
            out += ["else:"] + self.indent(other)
        return out

    def action(self, a):
        if a.cls == "print":
            return [f"print({self.expr(a.args)})"]
        if a.cls == "write":
            return [f"sys.stdout.write({self.expr(a.args)})"]
        if a.cls == "run":
            return ["sys.stdout.flush()",
                    f"subprocess.run({self.q(a.args[0])}, shell=True, "
                    "env={**os.environ, 'SPWN_RESPONSE': response})"]
        return [f"sys.exit({int(a.args[0]) if a.args else 0})"]


class NodeEmitter(Emitter):
    ext = ".js"
    cm = "//"
    and_, or_, not_ = " && ", " || ", "!"

    def q(self, s):
        return json.dumps(s, ensure_ascii=False)

    def cat(self, xs):
        return " + ".join(xs)

    def header(self):
        low = "" if self.cfg.case_sensitive else ".toLowerCase()"
        return ["#!/usr/bin/env node", "// Gerado por SPWN — não edite à mão.", '"use strict";',
                'const { execSync } = require("child_process");',
                "let response = process.argv[2];",
                "if (response === undefined) {",
                '  try { response = require("fs").readFileSync(0, "utf8").split("\\n")[0]; }',
                '  catch (e) { response = ""; }',
                "}", "response = response.trim();",
                f"const _r = response{low};", ""]

    def atom(self, k, a):
        q = self.q(a)
        return {"is": f"_r === {q}", "has": f"_r.includes({q})",
                "starts": f"_r.startsWith({q})", "any": "true"}[k]

    def branch(self, cond, then, other):
        out = [f"if ({cond}) {{"] + self.indent(then) + ["}"]
        if other:
            out = out[:-1] + ["} else {"] + self.indent(other) + ["}"]
        return out

    def action(self, a):
        if a.cls == "print":
            return [f'process.stdout.write({self.expr(a.args)} + "\\n");']
        if a.cls == "write":
            return [f"process.stdout.write({self.expr(a.args)});"]
        if a.cls == "run":
            return [f"try {{ execSync({self.q(a.args[0])}, {{ stdio: 'inherit', "
                    "env: { ...process.env, SPWN_RESPONSE: response } }); } catch (e) {}"]
        return [f"process.exit({int(a.args[0]) if a.args else 0});"]


class PhpEmitter(Emitter):
    ext = ".php"
    cm = "//"
    var = "$response"
    and_, or_, not_ = " && ", " || ", "!"

    def q(self, s):
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"

    def cat(self, xs):
        return " . ".join(xs)

    def header(self):
        low = ("$response" if self.cfg.case_sensitive else
               "function_exists('mb_strtolower') ? mb_strtolower($response) : strtolower($response)")
        return ["<?php", "// Gerado por SPWN — não edite à mão.",
                '$response = trim($argv[1] ?? (fgets(STDIN) ?: ""));',
                f"$_r = {low};", ""]

    def atom(self, k, a):
        q = self.q(a)
        return {"is": f"$_r === {q}", "has": f"str_contains($_r, {q})",
                "starts": f"str_starts_with($_r, {q})", "any": "true"}[k]

    branch = NodeEmitter.branch

    def action(self, a):
        if a.cls == "print":
            return [f'echo {self.expr(a.args)} . "\\n";']
        if a.cls == "write":
            return [f"echo {self.expr(a.args)};"]
        if a.cls == "run":
            return ['putenv("SPWN_RESPONSE=" . $response);', f"passthru({self.q(a.args[0])});"]
        return [f"exit({int(a.args[0]) if a.args else 0});"]


class BashEmitter(Emitter):
    ext = ".sh"
    var = '"$response"'
    and_, or_, not_ = " && ", " || ", "! "

    def wrap(self, x):
        return f"( {x} )"

    def q(self, s):
        return "'" + s.replace("'", "'\\''") + "'"

    def cat(self, xs):
        return "".join(xs)

    def header(self):
        low = '"$response"' if self.cfg.case_sensitive else '"${response,,}"'
        return ["#!/usr/bin/env bash", "# Gerado por SPWN — não edite à mão.",
                'if [ "$#" -gt 0 ]; then response="$1"; else IFS= read -r response || response=""; fi',
                'response="${response#"${response%%[![:space:]]*}"}"',
                'response="${response%"${response##*[![:space:]]}"}"',
                f"_r={low}", ""]

    def atom(self, k, a):
        q = self.q(a)
        return {"is": f'[[ "$_r" == {q} ]]', "has": f'[[ "$_r" == *{q}* ]]',
                "starts": f'[[ "$_r" == {q}* ]]', "any": "true"}[k]

    def branch(self, cond, then, other):
        out = [f"if {cond}; then"] + self.indent(then or [":"])
        if other:
            out += ["else"] + self.indent(other)
        return out + ["fi"]

    def action(self, a):
        if a.cls == "print":
            return [f"printf '%s\\n' {self.expr(a.args)}"]
        if a.cls == "write":
            return [f"printf '%s' {self.expr(a.args)}"]
        if a.cls == "run":
            return [f'SPWN_RESPONSE="$response" sh -c {self.q(a.args[0])}']
        return [f"exit {int(a.args[0]) if a.args else 0}"]


EMITTERS = {"python": PyEmitter, "node": NodeEmitter, "php": PhpEmitter, "bash": BashEmitter}
ALIASES = {"py": "python", "python3": "python", "js": "node", "nodejs": "node", "sh": "bash"}
EXT = {k: v.ext for k, v in EMITTERS.items()}


def canonical(target):
    t = ALIASES.get(target.lower(), target.lower())
    if t not in EMITTERS:
        raise SpwnTranspileError(
            f"alvo desconhecido {target!r}. Use: python, node, php ou bash")
    return t


def transpile(prog, target, cfg):
    target = canonical(target)
    acts = list(prog.setup) + [a for r in prog.rules for a in r.then + r.otherwise]
    for a in acts:
        if not ACTIONS[a.cls][2]:
            raise SpwnTranspileError(
                f"a ação {a.cls!r} só existe no interpretador (alvo {target})", a.line)
        if a.cls == "run" and not cfg.allow_run:
            raise SpwnTranspileError("ação 'run' desabilitada neste perfil", a.line)
    return EMITTERS[target](cfg).emit(prog)
SPWN_EOF
mkdir -p "$SPWN_HOME/bin"
cat > "$SPWN_HOME/bin/spwn" <<'SPWN_EOF'
#!/usr/bin/env python3
"""Executável CLI da SPWN. Uso: spwn arquivo.spw [-r "resposta"]"""
import os
import sys

HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
os.environ.setdefault("SPWN_HOME", HOME)
sys.path.insert(0, HOME)

from backend.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
SPWN_EOF
mkdir -p "$SPWN_HOME/examples"
cat > "$SPWN_HOME/examples/banner.spw" <<'SPWN_EOF'
#!/usr/bin/env spwn
# Banner SPWN — exibe a arte. Rode: spwn banner   (ou chmod +x e ./banner.spw)
<spwn>
spwn "print" == ("                       .:                             :.")
spwn "print" == ("                        -=                            +")
spwn "print" == ("                         :+*=-.                      .*.")
spwn "print" == ("                            -+***:                    +*.                                                                            -***-                  -*+.")
spwn "print" == ("                                 +**+                 :**-                                                                             :***+.          :    .+*-")
spwn "print" == ("                             +. .+*****.       -*-    =**=")
spwn "print" == ("                            .*- =******=    .+*= .:+****+.")
spwn "print" == ("                            -*: =  -***+.   +* :+=+*****=")
spwn "print" == ("             .....          .*= .  =****:  +*-     *****")
spwn "print" == (" .     .=+***********++:     :**++***. ..  +***++*****=                   =+:")
spwn "print" == ("   :-==-::.     .-*******+:   :******     .*****=:.+*:                  -*:")
spwn "print" == ("                  =*********-   -****+.   =***+.  ::    :=+*+=---      =*-")
spwn "print" == ("              ...  +*.  **+  :   .************+      :**+:           .**=")
spwn "print" == ("                :*= -=. .**=     :*************-  .=****..  -**+:. .+**=")
spwn "print" == ("                 .+*+.  **************.   .+*************=  -********+")
spwn "print" == ("                    :+*************=         -******=...-*********+:")
spwn "print" == ("                             -****+           -****.  .:-+***+-:.")
spwn "print" == ("                    ::-:-:    -***+           :****.")
spwn "print" == ("              .-*******-     :*****:          *********+=:..")
spwn "print" == ("           .*************************       :****************+.")
spwn "print" == ("         .+*********:   .*******+***************:. .:***- =: :*=")
spwn "print" == ("        -**=.     .:+=:. +**=.    -************-      =*=  :*: :--.")
spwn "print" == ("       :**-      -++=-=**+-    .  :****=..-*****.  .=-+***+**+.")
spwn "print" == ("      .*+      ..    .      :+:  :****-     -****=.  .+********.       .::::")
spwn "print" == ("     :+=                   =**********.  .  :******:    .+*************+=.   ..")
spwn "print" == ("  .=-.                   .*****.   =**.  +-:**-   +*:         :+++=-.                                                          +****-  = -*-   +***-  .- *-")
spwn "print" == ("                        -*******- :*+    .****++*::*:")
spwn "print" == ("                       .***+:   =*=.      +*****-  +.")
spwn "print" == ("                       :**=     -         .****=    .")
spwn "print" == ("                       .**-                 +**=")
spwn "print" == ("                        ***                  =***-")
spwn "print" == ("                         +*:                   :***+-")
spwn "print" == ("                         .*=                      .:=*+:")
spwn "print" == ("                          -=                           -=")
spwn "print" == ("                          =.                            ..")
spwn "print" == ("")
spwn "print" == ("")
spwn "print" == ("")
spwn "print" == ("       ____                              ___  ____")
spwn "print" == ("      / ___| _ __   __ ___      ___ __  / _ \\/ ___|")
spwn "print" == ("      \\___ \\| '_ \\ / _` \\ \\ /\\ / / '_ \\| | | \\___ \\")
spwn "print" == ("       ___) | |_) | (_| |\\ V  V /| | | | |_| |___) |")
spwn "print" == ("      |____/| .__/ \\__,_| \\_/\\_/ |_| |_|\\___/|____/")
spwn "print" == ("            |_|")
</spwn>
SPWN_EOF
mkdir -p "$SPWN_HOME/examples"
cat > "$SPWN_HOME/examples/demo.spw" <<'SPWN_EOF'
#!/usr/bin/env spwn
# Demo SPWN — rode: spwn examples/demo.spw -r "oi"   (ou chmod +x e ./demo.spw -r oi)
<spwn>
spwn "print" == ("== SPWN demo ==")

spawn-def_class == ("saudacao") if response-is("oi") or response-is("olá")
      spwn "print" == ("Olá! Você disse: {response}")

spawn-def_class == ("memoria") if response-has("meu nome é") and not response-has("não")
      spwn "save" == ("ultima", "{response}")
      spwn "print" == ("Guardei: {response}")

spawn-def_class == ("ultima") if response-is("ultima")
      spwn "load" == ("ultima")

spawn-def_class == ("data") if response-is("data")
      spwn "run" == ("date")

spawn-def_class == ("tchau") if response-starts("tchau")
      spwn "print" == ("Até logo!")
      spwn "exit" == ("0")
else
      spwn "write" == ("")
</spwn>
SPWN_EOF
mkdir -p "$SPWN_HOME/examples"
cat > "$SPWN_HOME/examples/ola.spw" <<'SPWN_EOF'
<spwn>
spawn-def_class == ("print") if
      response-is("oi") spwn "print" == ("Olá")
</spwn>
SPWN_EOF
mkdir -p "$SPWN_HOME/files"
cat > "$SPWN_HOME/files/__init__.py" <<'SPWN_EOF'
"""Manipulação de arquivos e persistência de dados da SPWN."""
SPWN_EOF
mkdir -p "$SPWN_HOME/files"
cat > "$SPWN_HOME/files/fileio.py" <<'SPWN_EOF'
"""E/S de arquivos restrita a um diretório (sandbox) + escrita atômica."""
import os

from backend.errors import SpwnRuntimeError


def atomic_write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = f"{path}.tmp{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


class Sandbox:
    """Só permite acessar caminhos dentro de `base` (bloqueia ../ e symlinks de fuga)."""

    def __init__(self, base):
        self.base = os.path.realpath(base)

    def resolve(self, rel):
        p = os.path.realpath(os.path.join(self.base, rel))
        if os.path.commonpath([self.base, p]) != self.base:
            raise SpwnRuntimeError(f"caminho fora da pasta de dados: {rel!r}")
        return p

    def read(self, rel):
        try:
            with open(self.resolve(rel), encoding="utf-8") as f:
                return f.read()
        except OSError as e:
            raise SpwnRuntimeError(f"erro ao ler {rel!r}: {e.strerror}")

    def write(self, rel, text):
        try:
            atomic_write(self.resolve(rel), text)
        except OSError as e:
            raise SpwnRuntimeError(f"erro ao gravar {rel!r}: {e.strerror}")

    def append(self, rel, text):
        try:
            p = self.resolve(rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "a", encoding="utf-8") as f:
                f.write(text)
        except OSError as e:
            raise SpwnRuntimeError(f"erro ao anexar em {rel!r}: {e.strerror}")
SPWN_EOF
mkdir -p "$SPWN_HOME/files"
cat > "$SPWN_HOME/files/store.py" <<'SPWN_EOF'
"""Persistência chave→valor em JSON (store.json), gravação atômica."""
import json
import os

from backend.errors import SpwnRuntimeError
from files.fileio import atomic_write


class Store:
    def __init__(self, base):
        self.path = os.path.join(base, "store.json")

    def _load(self):
        try:
            with open(self.path, encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            return {}
        except (OSError, json.JSONDecodeError) as e:
            raise SpwnRuntimeError(f"store.json ilegível: {e}")
        return data if isinstance(data, dict) else {}

    def get(self, key, default=""):
        return self._load().get(key, default)

    def set(self, key, value):
        data = self._load()
        data[key] = value
        try:
            atomic_write(self.path, json.dumps(data, ensure_ascii=False, indent=2))
        except OSError as e:
            raise SpwnRuntimeError(f"erro ao gravar store.json: {e.strerror}")

    def delete(self, key):
        data = self._load()
        if data.pop(key, None) is not None:
            atomic_write(self.path, json.dumps(data, ensure_ascii=False, indent=2))

    def keys(self):
        return sorted(self._load())
SPWN_EOF
mkdir -p "$SPWN_HOME/."
cat > "$SPWN_HOME/install.sh" <<SPWN_EOF
#!/usr/bin/env bash
# Instala o comando \`spwn\` no PATH (Termux ou Linux).
set -e
SPWN_HOME="\$(cd "\$(dirname "\$0")" && pwd)"
export SPWN_HOME

# Detecta Python
_py() {
    for c in python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8 python3 python; do
        command -v "\$c" >/dev/null 2>&1 && echo "\$c" && return
    done
    echo python3
}
PYTHON="\$(_py)"

if ! command -v "\$PYTHON" >/dev/null 2>&1; then
    if [[ -d /data/data/com.termux/files/usr ]]; then
        pkg install -y python || true
    else
        echo "Python não encontrado. Instale python3."
        exit 1
    fi
fi

chmod +x "\$SPWN_HOME/bin/spwn"

# Link no PATH
if [[ -d /data/data/com.termux/files/usr ]]; then
    LINK_DIR="\${PREFIX:-/data/data/com.termux/files/usr}/bin"
else
    LINK_DIR="\${PREFIX:-/usr/local}/bin"
fi
mkdir -p "\$LINK_DIR"
ln -sf "\$SPWN_HOME/bin/spwn" "\$LINK_DIR/spwn" 2>/dev/null || {
    # sem permissão de escrita em /usr/local — usa ~/.local/bin
    LINK_DIR="\$HOME/.local/bin"
    mkdir -p "\$LINK_DIR"
    ln -sf "\$SPWN_HOME/bin/spwn" "\$LINK_DIR/spwn"
}

# Garante PATH nos profiles
for profile in "\$HOME/.bashrc" "\$HOME/.profile" "\$HOME/.bash_profile" "\$HOME/.zshrc"; do
    if [[ -f "\$profile" ]] || [[ "\$profile" == "\$HOME/.bashrc" ]]; then
        if ! grep -qF "\$SPWN_HOME/bin" "\$profile" 2>/dev/null; then
            printf '\\nexport SPWN_HOME="%s"\\nexport PATH="%s/bin:\$PATH"\\n' "\$SPWN_HOME" "\$SPWN_HOME" >> "\$profile"
        fi
    fi
done

echo "spwn instalado em \$LINK_DIR/spwn"
echo "SPWN_HOME=\$SPWN_HOME"
echo "Teste: spwn \$SPWN_HOME/examples/ola.spw -r oi"
echo "Opcional (alvos de transpile): nodejs / php"
SPWN_EOF
mkdir -p "$SPWN_HOME/settings"
cat > "$SPWN_HOME/settings/__init__.py" <<'SPWN_EOF'
"""Configuração, perfis de execução e flags de ambiente da SPWN."""
SPWN_EOF
mkdir -p "$SPWN_HOME/settings"
cat > "$SPWN_HOME/settings/config.py" <<'SPWN_EOF'
"""Carregamento de configuração: spwn.json < perfil < variáveis de ambiente."""
import json
import os
from dataclasses import dataclass, field
from typing import List

from backend.errors import SpwnError

HERE = os.path.dirname(os.path.abspath(__file__))

DEFAULTS = {
    "case_sensitive": False,
    "repl_prompt": "spwn> ",
    "exit_words": ["sair", "exit", "quit"],
    "data_dir": "files/data",
    "shell_timeout": 30,
    "allow_run": True,
    "default_target": "python",
}


@dataclass
class Config:
    profile: str = "default"
    case_sensitive: bool = False
    repl_prompt: str = "spwn> "
    exit_words: List[str] = field(default_factory=lambda: ["sair", "exit", "quit"])
    data_dir: str = "files/data"
    shell_timeout: float = 30
    allow_run: bool = True
    default_target: str = "python"


def spwn_home():
    return os.environ.get("SPWN_HOME") or os.path.dirname(HERE)


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as e:
        raise SpwnError(f"configuração inválida em {path}: {e}")


def load(profile=None):
    home = spwn_home()
    user = _read(os.path.join(HERE, "spwn.json"))
    profiles = _read(os.path.join(HERE, "profiles.json"))
    name = profile or os.environ.get("SPWN_PROFILE") or user.get("profile") or "default"
    if name != "default" and name not in profiles:
        raise SpwnError(f"perfil desconhecido {name!r}. Disponíveis: {', '.join(sorted(profiles))}")

    data = dict(DEFAULTS)
    data.update({k: v for k, v in user.items() if k in DEFAULTS})
    data.update({k: v for k, v in profiles.get(name, {}).items() if k in DEFAULTS})
    if os.environ.get("SPWN_DATA_DIR"):
        data["data_dir"] = os.environ["SPWN_DATA_DIR"]

    d = os.path.expanduser(str(data["data_dir"]))
    data["data_dir"] = d if os.path.isabs(d) else os.path.join(home, d)
    data["case_sensitive"] = bool(data["case_sensitive"])
    data["allow_run"] = bool(data["allow_run"])
    try:
        data["shell_timeout"] = float(data["shell_timeout"])
    except (TypeError, ValueError):
        raise SpwnError("shell_timeout deve ser um número")
    return Config(profile=name, **data)
SPWN_EOF
mkdir -p "$SPWN_HOME/settings"
cat > "$SPWN_HOME/settings/env.sh" <<SPWN_EOF
# Flags de ambiente da SPWN — use: source settings/env.sh
export SPWN_HOME="$SPWN_HOME"
export PATH="\$SPWN_HOME/bin:\$PATH"
# export SPWN_PROFILE=default        # default | strict | chat | safe
# export SPWN_DATA_DIR="\$HOME/.spwn" # onde save/load/fwrite/fread gravam
SPWN_EOF
mkdir -p "$SPWN_HOME/settings"
cat > "$SPWN_HOME/settings/profiles.json" <<'SPWN_EOF'
{
  "default": {},
  "strict": { "case_sensitive": true },
  "chat": { "repl_prompt": "você> ", "shell_timeout": 10 },
  "safe": { "allow_run": false }
}
SPWN_EOF
mkdir -p "$SPWN_HOME/settings"
cat > "$SPWN_HOME/settings/spwn.json" <<'SPWN_EOF'
{
  "profile": "default",
  "case_sensitive": false,
  "repl_prompt": "spwn> ",
  "exit_words": ["sair", "exit", "quit"],
  "data_dir": "files/data",
  "shell_timeout": 30,
  "allow_run": true,
  "default_target": "python"
}
SPWN_EOF
mkdir -p "$SPWN_HOME/strings"
cat > "$SPWN_HOME/strings/__init__.py" <<'SPWN_EOF'
"""Dicionários de palavras-chave, tokens e utilitários de string da SPWN."""
SPWN_EOF
mkdir -p "$SPWN_HOME/strings"
cat > "$SPWN_HOME/strings/keywords.py" <<'SPWN_EOF'
"""Dicionário de palavras-chave da linguagem SPWN."""

TAG_OPEN = "<spwn>"
TAG_CLOSE = "</spwn>"

KW_DEF = "spawn-def_class"
KW_CALL = "spwn"
KW_IF = "if"
KW_ELSE = "else"
KW_AND = "and"
KW_OR = "or"
KW_NOT = "not"

RESERVED = {KW_DEF, KW_CALL, KW_IF, KW_ELSE, KW_AND, KW_OR, KW_NOT}

# condição -> (tipo interno, exige argumento?)
CONDITIONS = {
    "response-is": ("is", True),
    "response-has": ("has", True),
    "response-starts": ("starts", True),
    "response-any": ("any", False),
}

# ação -> (mín. args, máx. args, existe nos transpiladores?)
ACTIONS = {
    "print": (1, 16, True),
    "write": (1, 16, True),
    "run": (1, 1, True),
    "exit": (0, 1, True),
    "save": (2, 2, False),
    "load": (1, 1, False),
    "fwrite": (2, 2, False),
    "fappend": (2, 2, False),
    "fread": (1, 1, False),
}

INTERP_VAR = "{response}"

# Extensões de arquivo SPWN (a primeira é a oficial; .spwn segue aceita)
EXTENSIONS = (".spw", ".spwn")
SPWN_EOF
mkdir -p "$SPWN_HOME/strings"
cat > "$SPWN_HOME/strings/strutil.py" <<'SPWN_EOF'
"""Tratamento de strings: escapes e interpolação de {response}."""

_ESC = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
_VAR = "{response}"


def unescape(raw):
    """Converte \\n, \\t, \\", \\\\ em seus caracteres reais (raw sem aspas)."""
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            out.append(_ESC.get(n, "\\" + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def interpolate(s, response):
    return s.replace(_VAR, response)


def split_interp(s):
    """Divide em partes: ('lit', texto) ou ('resp', None)."""
    parts = []
    for i, chunk in enumerate(s.split(_VAR)):
        if i:
            parts.append(("resp", None))
        if chunk:
            parts.append(("lit", chunk))
    return parts


def join_args(args):
    """Junta vários argumentos com um espaço, já dividido em partes."""
    parts = []
    for i, a in enumerate(args):
        if i:
            parts.append(("lit", " "))
        parts += split_interp(a)
    return parts
SPWN_EOF
mkdir -p "$SPWN_HOME/strings"
cat > "$SPWN_HOME/strings/tokens.py" <<'SPWN_EOF'
"""Definição de tokens e da gramática léxica da SPWN."""
import re
from dataclasses import dataclass


class T:
    TAG_OPEN = "TAG_OPEN"
    TAG_CLOSE = "TAG_CLOSE"
    STRING = "STRING"
    IDENT = "IDENT"
    EQ = "EQ"
    LPAREN = "LPAREN"
    RPAREN = "RPAREN"
    COMMA = "COMMA"
    EOF = "EOF"


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int
    col: int


# A ordem importa: a primeira alternativa que casar vence.
SPEC = [
    ("COMMENT", r"\#[^\n]*"),
    ("WS", r"[ \t\r\n]+"),
    (T.TAG_CLOSE, r"</spwn>"),
    (T.TAG_OPEN, r"<spwn>"),
    (T.STRING, r'"(?:\\.|[^"\\\n])*"'),
    (T.EQ, r"=="),
    (T.LPAREN, r"\("),
    (T.RPAREN, r"\)"),
    (T.COMMA, r","),
    (T.IDENT, r"[A-Za-z_][A-Za-z0-9_\-]*"),
]

MASTER = re.compile("|".join(f"(?P<{n}>{p})" for n, p in SPEC))
SPWN_EOF
mkdir -p "$SPWN_HOME/tests"
cat > "$SPWN_HOME/tests/test_spwn.py" <<'SPWN_EOF'
import io, os, shutil, subprocess, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ["SPWN_DATA_DIR"] = tempfile.mkdtemp(prefix="spwn_test_")

from backend.errors import SpwnError, SpwnSyntaxError, SpwnTranspileError
from backend.interpreter import Interpreter
from backend.parser import parse
from backend.transpiler import transpile
from settings import config

OLA = open(os.path.join(ROOT, "examples", "ola.spw"), encoding="utf-8").read()
CFG = config.load()


def run(src, resp, cfg=CFG):
    out = io.StringIO()
    code = Interpreter(cfg, out).run(parse(src), resp)
    return out.getvalue(), code


class Interp(unittest.TestCase):
    def test_exemplo(self):
        self.assertEqual(run(OLA, "oi")[0], "Olá\n")
        self.assertEqual(run(OLA, "OI")[0], "Olá\n")      # case-insensitive
        self.assertEqual(run(OLA, "xyz")[0], "")

    def test_bool_else_exit(self):
        src = '''<spwn>
        spawn-def_class == ("a") if (response-is("x") or response-has("y")) and not response-has("z")
            spwn "print" == ("sim {response}")
        else
            spwn "print" == ("nao")
        spawn-def_class == ("b") if response-is("q")
            spwn "exit" == ("3")
        </spwn>'''
        self.assertEqual(run(src, "x")[0], "sim x\n")
        self.assertEqual(run(src, "azy")[0], "nao\n")
        self.assertEqual(run(src, "yz")[0], "nao\n")
        self.assertEqual(run(src, "q")[1], 3)

    def test_store_files(self):
        src = '''<spwn>
        spawn-def_class == ("s") if response-any()
            spwn "save" == ("k", "{response}")
            spwn "load" == ("k")
            spwn "fwrite" == ("a/b.txt", "olá")
            spwn "fread" == ("a/b.txt")
        </spwn>'''
        self.assertEqual(run(src, "valor")[0], "valor\nolá")

    def test_sandbox(self):
        src = '<spwn>\nspwn "fread" == ("../../etc/passwd")\n</spwn>'
        with self.assertRaises(SpwnError):
            run(src, "")

    def test_perfil_safe_bloqueia_run(self):
        src = '<spwn>\nspwn "run" == ("echo oi")\n</spwn>'
        with self.assertRaises(SpwnError):
            run(src, "", config.load("safe"))


class Extensoes(unittest.TestCase):
    def test_resolucao(self):
        from backend.cli import resolve_source
        d = tempfile.mkdtemp()
        for nome in ("a.spw", "b.spwn", "c.spw", "c.spwn"):
            open(os.path.join(d, nome), "w").write(OLA)
        j = lambda n: os.path.join(d, n)
        self.assertEqual(resolve_source(j("a")), j("a.spw"))
        self.assertEqual(resolve_source(j("b")), j("b.spwn"))
        self.assertEqual(resolve_source(j("c")), j("c.spw"))      # .spw tem prioridade
        self.assertEqual(resolve_source(j("b.spwn")), j("b.spwn"))
        with self.assertRaises(SpwnError):
            resolve_source(j("nada"))

    def test_shebang_e_cli(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "x.spw")
        open(p, "w", encoding="utf-8").write("#!/usr/bin/env spwn\n" + OLA)
        for arg in (p, p[:-4]):
            r = subprocess.run([sys.executable, os.path.join(ROOT, "bin", "spwn"), arg, "-r", "oi"],
                               capture_output=True, text=True)
            self.assertEqual((r.stdout, r.returncode), ("Olá\n", 0), r.stderr)


class Erros(unittest.TestCase):
    def bad(self, src):
        with self.assertRaises(SpwnSyntaxError):
            parse(src)

    def test_erros(self):
        self.bad('spwn "print" == ("x")')                                   # fora do bloco
        self.bad('<spwn>\nspwn "print" == ("x")\n')                         # sem fechar
        self.bad('<spwn>\nspwn "foo" == ("x")\n</spwn>')                    # ação desconhecida
        self.bad('<spwn>\nspwn "run" == ("echo {response}")\n</spwn>')      # injeção
        self.bad('<spwn>\nspawn-def_class == ("a\\nb") if response-any()\n</spwn>')
        self.bad('<spwn>\nspawn-def_class == ("a") spwn "print" == ("x") else spwn "print" == ("y")\n</spwn>')
        self.bad('<spwn>\nspwn "print" == ("aberta)\n</spwn>')


class Transpila(unittest.TestCase):
    SRC = '''<spwn>
    spawn-def_class == ("a") if (response-is("o'i") or response-starts("x")) and not response-has("$(z)")
        spwn "print" == ("Olá '{response}' \\"q\\" $HOME `id`")
        spwn "write" == ("a", "b")
    else
        spwn "print" == ("nao")
    spawn-def_class == ("b") if response-is("sair")
        spwn "run" == ("echo env=$SPWN_RESPONSE")
        spwn "exit" == ("4")
    </spwn>'''
    CASES = [
        ("python", ["python3"], "o'i"),
        ("node", ["node"], "o'i"),
        ("php", ["php"], "o'i"),
        ("bash", ["bash"], "o'i"),
    ]

    def test_alvos(self):
        prog = parse(self.SRC)
        for target, rt, _ in self.CASES:
            code = transpile(prog, target, CFG)
            exe = shutil.which(rt[0])
            if not exe:
                print(f"[pulado: {rt[0]} ausente]")
                continue
            ext = {"python": ".py", "node": ".js", "php": ".php", "bash": ".sh"}[target]
            with tempfile.NamedTemporaryFile("w", suffix=ext, delete=False, encoding="utf-8") as f:
                f.write(code)
            try:
                for resp in ["o'i", "X1", "z", "$(z)", "sair"]:
                    exp_out, exp_code = run(self.SRC, resp)
                    r = subprocess.run([exe, f.name, resp], capture_output=True, text=True)
                    if resp == "sair":
                        exp_out += "env=sair\n"     # 'run' do interpretador escreve direto no fd
                    self.assertEqual((r.stdout, r.returncode), (exp_out, exp_code),
                                     f"{target} resp={resp!r}\n{code}\n{r.stderr}")
            finally:
                os.unlink(f.name)

    def test_somente_interpretador(self):
        prog = parse('<spwn>\nspwn "save" == ("a", "b")\n</spwn>')
        with self.assertRaises(SpwnTranspileError):
            transpile(prog, "python", CFG)

    def test_alvo_invalido(self):
        with self.assertRaises(SpwnTranspileError):
            transpile(parse(OLA), "cobol", CFG)


if __name__ == "__main__":
    unittest.main(verbosity=2)
SPWN_EOF
chmod +x "$SPWN_HOME/bin/spwn" "$SPWN_HOME/install.sh"
bash "$SPWN_HOME/install.sh"

# Garante PATH na sessão atual
export PATH="$SPWN_HOME/bin:$PATH"

# Banner de boas-vindas (se o exemplo existir)
if [[ -f "$SPWN_HOME/examples/banner.spw" ]]; then
    "$PYTHON" "$SPWN_HOME/bin/spwn" "$SPWN_HOME/examples/banner" 2>/dev/null ||     "$SPWN_HOME/bin/spwn" "$SPWN_HOME/examples/banner" 2>/dev/null || true
fi

echo ""
echo "============================================"
echo " SPWN instalado com sucesso ($ENV_NAME)"
echo " SPWN_HOME=$SPWN_HOME"
echo " Comando: spwn"
echo " Exemplo: spwn $SPWN_HOME/examples/ola.spw -r oi"
echo "============================================"
