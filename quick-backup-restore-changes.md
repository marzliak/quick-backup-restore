# Quick Backup & Restore — Plano de Alterações

Baseado no relatório de segurança do ClawHub. Cada item tem o arquivo, o quê mudar, e a ordem.

---

## 1. Reescrever `bin/customize.sh` — eliminar `openclaw agent ask`

**Problema:** O script manda workspace listing pro modelo via `openclaw agent ask --no-memory`. Mesmo com filtros (*.env, secrets.*), nomes de arquivos podem vazar info sensível.

**Solução:** Subuir a lógica de sugestão pro bash puro. Sem chamada de API.

### Mudanças em `bin/customize.sh`:

- Remover toda a seção que chama `openclaw agent ask` (whitelist e blacklist)
- Substituir por análise local via bash:
  - **Whitelist:** usar `find` pra detectar arquivos/diretórios fora dos paths padrão que parecem importantes (scripts em `~/bin`, configs em `~/.config`, chaves SSH em `~/.ssh` se não estiver na lista, etc)
  - **Blacklist:** usar lista hardcoded de padrões comuns (`node_modules/`, `*.log`, `*.cache`, `__pycache__/`, `.venv/`, `*.mp4`, `*.mkv`, `*.iso`, `*.zip`, `*.tar.gz`, `cache/`, `tmp/`)
- Manter a confirmação do usuário antes de aplicar
- Manter o sanitize de entries (`_sanitize_entry`)
- Manter o backup de config.yaml antes de alterar

### Novo fluxo do customize.sh:

```
1. Scan workspace (find, depth 3, excluindo .git/.env/secrets)
2. Detectar paths extras: comparar find com BACKUP_PATHS atuais
3. Sugerir exclusões baseado em padrões hardcoded + tamanho de arquivos
4. Mostrar sugestões ao usuário
5. Pedir confirmação
6. Aplicar ao config.yaml
7. Re-run setup --skip-backup
```

### Referências nos prompts:
- Deletar `prompts/whitelist.txt` e `prompts/blacklist.txt` (não serão mais usados)

---

## 2. Adicionar flag `--no-system-install` no `bin/setup.sh`

**Problema:** Setup roda como root e modifica sistema (/usr/local/bin, /etc/cron.d, apt-get) sem opção de pular.

**Solução:** Flag que só prepara o repo (cria diretório, gera senha, init restic, roda backup).

### Mudanças em `bin/setup.sh`:

Adicionar no início, junto com o `--skip-backup`:
```bash
SKIP_BACKUP=false
NO_SYSTEM=false
for arg in "$@"; do
    [[ "$arg" == "--skip-backup" ]] && SKIP_BACKUP=true
    [[ "$arg" == "--no-system-install" ]] && NO_SYSTEM=true
done
```

Envolver toda a seção de instalação de dependências + cron + binário em:
```bash
if [[ "$NO_SYSTEM" == "true" ]]; then
    echo "==> --no-system-install: skipping dep install, cron, binary"
    # Só verificar se deps existem
    tc_check_deps || { echo "ERROR: deps missing. Install manually or run without --no-system-install"; exit 1; }
else
    # código atual de install_pkg, apt-get, cron, cp binário
fi
```

### Resumo do que --no-system-install faz:
- ✅ Cria diretório do repo
- ✅ Gera senha
- ✅ Init restic
- ✅ Roda backup inicial (se --skip-backup não setado)
- ❌ Não instala pacotes (apt-get)
- ❌ Não copia binário pra /usr/local/bin
- ❌ Não registra cron
- ❌ Não mexe em permissões de config.yaml (pq não precisa de root)

---

## 3. Perguntar antes de instalar pacotes no `bin/setup.sh`

**Problema:** `apt-get update -qq` e `install_pkg` rodam sem confirmação.

**Solução:** Adicionar prompt antes de instalar, com flag `--assume-yes` pra CI/automated.

### Mudanças em `bin/setup.sh`:

Adicionar flag:
```bash
ASSUME_YES=false
[[ "$arg" == "--assume-yes" || "$arg" == "-y" ]] && ASSUME_YES=true
```

Antes do bloco de instalação:
```bash
if [[ "$NO_SYSTEM" != "true" ]]; then
    # Listar o que seria instalado
    MISSING_PKGS=()
    for pkg in restic curl jq; do
        command -v "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
    done
    if ! command -v yq &>/dev/null; then
        MISSING_PKGS+=("yq (from GitHub)")
    fi

    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
        echo "==> The following dependencies will be installed:"
        for p in "${MISSING_PKGS[@]}"; do echo "    - $p"; done
        if [[ "$ASSUME_YES" != "true" ]]; then
            read -rp "Proceed? [y/N]: " CONFIRM
            [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
        fi
    fi

    apt-get update -qq
    # ... resto da instalação
fi
```

---

## 4. Atualizar `skill.json` — bump versão

```json
{
  "version": "1.1.0"
}
```

---

## 5. Atualizar `CHANGELOG.md`

Adicionar entrada no topo:

```markdown
## 1.1.0 — Security hardening (2026-04-09)

### Changes
- customize.sh: replaced `openclaw agent ask` with pure bash analysis — no data leaves the machine
- setup.sh: added `--no-system-install` flag for repo-only setup without root modifications
- setup.sh: added dependency install confirmation prompt (override with `--assume-yes`)
- Deleted `prompts/whitelist.txt` and `prompts/blacklist.txt` (no longer needed)

### Security
- Eliminates workspace listing exfiltration risk flagged by ClawHub security scan
- Users can now set up backup repo without modifying system files
```

---

## 6. Atualizar `README.md`

- Seção "Quick start" adicionar opção com `--no-system-install`
- Seção nova "Flags" documentando `--skip-backup`, `--no-system-install`, `--assume-yes`
- Mencionar que `customize.sh` agora roda 100% local (sem API calls)

---

## 7. Atualizar `SKILL.md`

- Remover qualquer menção a `openclaw agent ask` ou AI-assisted customization
- Atualizar descrição do customize.sh pra "local bash analysis"
- Adicionar nota sobre `--no-system-install`

---

## Ordem de execução

1. `bin/customize.sh` + deletar `prompts/` — o mais crítico (exfiltração)
2. `bin/setup.sh` — flags `--no-system-install` e `--assume-yes`
3. `skill.json` — bump versão
4. `CHANGELOG.md` — documentar mudanças
5. `README.md` — documentar flags
6. `SKILL.md` — atualizar descrição do customize
7. `clawhub publish` — subir pro registry

---

## Arquivos que serão modificados

| Arquivo | Ação |
|---------|------|
| `bin/customize.sh` | Reescrever (remover openclaw agent ask) |
| `bin/setup.sh` | Adicionar flags --no-system-install e --assume-yes |
| `prompts/whitelist.txt` | **Deletar** |
| `prompts/blacklist.txt` | **Deletar** |
| `skill.json` | Bump versão 1.0.0 → 1.1.0 |
| `CHANGELOG.md` | Adicionar entrada 1.1.0 |
| `README.md` | Adicionar seção de flags |
| `SKILL.md` | Atualizar descrição do customize |
