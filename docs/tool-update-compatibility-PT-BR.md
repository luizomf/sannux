# Auditoria de compatibilidade das ferramentas flutuantes

Mudança de política autorizada pelo dono: [sannux #28](https://github.com/luizomf/sannux/issues/28).
[English](tool-update-compatibility.md).

Somente a base Debian fica fixada. Esta auditoria registra observações, não novas
exigências de versão. Veja o [contrato](template-contract.md) e o
[checklist de manutenção](../AGENTS.md#shared-runtime-maintenance-checklist).

## Inventário e decisões

| Superfície | Constatação e decisão |
| --- | --- |
| Dez Dockerfiles | Removidos versão/SHA do RTK e versão exata do npm; majors numéricos do NodeSource trocados por `setup_lts.x`. As dez linhas FROM do Debian permanecem idênticas byte a byte. |
| RTK | Latest é resolvido uma vez para uma tag validada. Archive e `checksums.txt` vêm dessa tag; exige-se exatamente um checksum correspondente, verificado antes da extração, e compara-se a versão do executável com a tag resolvida. Os nomes dos artefatos Linux amd64 musl e arm64 GNU e o membro `rtk` continuam suportados. Ausência de artefatos/checksums interrompe o build. |
| Node/npm | [Canal LTS oficial do NodeSource](https://deb.nodesource.com/setup_lts.x), depois `npm@latest` com `--engine-strict`. Na validação, Node 24.20.0 satisfez a engine `^22.22.2 || ^24.15.0 || >=26.0.0` do npm 12.0.2. O sannux não seleciona major numérico do Node. |
| Codex | Os quatro consumidores instalam latest do npm e verificam versão e interfaces exec/app-server. A [PR #26](https://github.com/luizomf/sannux/pull/26) documentou diferenças de catálogo daquela conta entre 0.151.0 e 0.153.3, não a necessidade de permanecer exatamente em 0.153.3. As antigas assertions contrariavam a política do dono e já falhavam no baseline. Foram substituídas por regressões da política flutuante e checks offline de CLI, não por uma promessa sobre acesso da conta. |
| Config/catálogo Codex | Inspecionados renderização do setup, TOML e JSON versionado. O [protocolo 0.153.4](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/protocol/src/openai_models.rs) ainda aceita `shell_command` como alias e promove `base_instructions` legado pelo adaptador ModelsResponse. Os metadados obrigatórios estão presentes. Alguns flags legados não correspondem mais a campos de ModelInfo; não presuma que controlam o comportamento atual. Catálogo/config permanecem intactos: IDs de modelos, enums, limites de contexto e `/v1` não são pins. Não houve listagem de modelos nem geração. |
| uv | Pi copia os binários oficiais de `uv:latest` para `/usr/local/bin`. O smoke existente verifica caminhos, uso não-root e comportamento real de venv/run, não versão exata. O manifesto latest inclui linux/amd64 e linux/arm64. |
| Hermes | O instalador existente do `main` upstream continua flutuante. Seu [pyproject](https://github.com/NousResearch/hermes-agent/blob/main/pyproject.toml) exige Python `>=3.11,<3.14` e possui pins/regras de idade deliberados; o instalador escolhe Python 3.11 atualmente. O [package.json](https://github.com/NousResearch/hermes-agent/blob/main/package.json) raiz exige Node `^22.22.0 || ^24.11.0 || >=26.0.0` e npm `<11.10.0 || >=11.17.0`. A [PR #16](https://github.com/luizomf/sannux/pull/16) explica a falha do npm embarcado anterior. Preservados locks uv/npm, engine-strict e runtimes do instalador; não reescrever dependências do upstream. `uv sync --locked` e `npm ci` continuam. |
| Outros CLIs/instaladores | Gemini, Claude/Ollama, OpenCode, Pi e playwright-core já usam distribuições npm flutuantes. O link de compatibilidade do ripgrep vendorizado pelo Gemini permanece. Antigravity agora instala no build em `/usr/local/bin` pelo instalador oficial com SHA512; Claude Code usa o instalador oficial stable e copia o binário nativo para lá. Ambos funcionam sem executável instalado na home. Overrides intencionais no PATH da home continuam possíveis. |
| Scripts/consumidores | `just rebuild` agora usa `--no-cache --pull`; build normal continua com cache. `scripts/rebuild_all_templates` herda a receita, mas também chama setup (o setup remote-dev inicia SSH): foi inspecionado, não executado como se apenas construísse imagens. Setup, Compose e browser-fetch foram inspecionados e preservados, exceto os dois entrypoints dos CLIs nativos. Não há snapshot de extensão nem lockfile de dependências versionado no sannux. Extensões montadas, inbox e Daily separado não foram carregados nem modificados. |

Versão da sintaxe Dockerfile, versões de schema/protocolo, exemplos de modelos,
portas e UID/GID não foram tratados como pins. Pacotes Debian continuam limitados
aos repositórios da distribuição escolhida, não ao latest de cada upstream.

## Validação real

- Baseline `just check`: falhou nas três exigências antigas de pin do Codex/Pi.
- Novo guard global: RED nos dez Dockerfiles, depois GREEN. O teste de bypass
  por tag RTK literal também falhou antes do guard e passou depois.
- `just check` executa o conjunto estrutural/de segurança original e oito testes
  de regressão, incluindo mutações por template para pins RTK/npm/Node, perda
  de checksum/arquitetura, pins/checks Codex, destino/digest uv, flags de rebuild,
  locks Hermes e alteração insegura de guard de mount.
- Dez Compose: ambiente mínimo sintético de subprocesso, `--env-file /dev/null`,
  todos os profiles e `config --no-env-resolution --format json`. Verificados
  contextos/UID padrão, destinos workspace/home e guards; caminhos obrigatórios
  ausentes foram rejeitados. Nenhum `.env` real foi carregado ou impresso.
- Pi: `docker build --no-cache --pull` real, candidata `sannux/pi:policy-28`,
  linux/arm64. Node 24.20.0, npm 12.0.2, RTK 0.48.0, Pi 0.85.1,
  Codex 0.153.4 e uv/uvx 0.12.10. `check-uv.sh` e `check-tools.sh` passaram
  não-root, com home substituta vazia, raiz somente-leitura, sem rede externa
  nem mounts do host. Cobrem uv venv/run, engines Node, RTK proxy, flags Pi/Codex,
  transformação TypeScript pelo esbuild nativo e fixture loopback com JavaScript
  realmente renderizado pelo browser-fetch/Chromium Debian/playwright.
- Metadados públicos npm: Gemini 0.58.0 e playwright-core 1.63.0 exigem Node
  `>=20`; Claude Code npm 2.1.263 exige `>=22.0.0`; OpenCode 1.18.29 não declara
  engine Node. Conferir metadados não substitui testes de runtime do template.
- npm avisou sobre scripts de dependências bloqueados; o binário nativo fornecido
  pelo esbuild passou no teste. Não foi adicionada permissão genérica de scripts.
- Antigravity e Claude: builds candidatos reais reutilizaram as novas camadas
  comuns; entrypoints offline não-root com home nova passaram: agy 1.1.27 e
  Claude 2.1.236. Tags: `sannux/agy:policy-28`, `sannux/claude-code:policy-28`.
  CLIs sintéticos na home também verificaram o encaminhamento literal de
  argumentos e stdin pelos dois entrypoints, sem invocar modelo.
- Codex: config gerada pelo setup real em contêiner isolado; initialize +
  `config/read` do app-server aceitaram provider/modelo sintéticos. Sem chamadas
  de modelo/provider; a inspeção do schema do catálogo foi no código-fonte, não
  um teste de catálogo ao vivo ou de comportamento do modelo.
- Hermes no commit `22c5684b983eac6a81ee015ae80296c4b3dbf5bb`: na candidata Pi
  descartável e sem credenciais, passaram `uv sync --locked --dry-run --extra all
  --extra messaging --python /usr/bin/python3` e `npm ci --dry-run --ignore-scripts
  --no-audit --no-fund` em `web`. Isso verifica resolução, engines e locks,
  não o build completo, dashboard ou runtime do Hermes.
- Os dois archives Linux do RTK foram baixados e verificados contra os SHA256
  correspondentes do upstream; membro executável conferido. Runtime só em arm64.
- `just --list`, dry-run do rebuild, sintaxe shell e `git diff --check` passaram.

## Limites

Sem build completo amd64, sem rebuild dos outros sete templates, sem execução
credenciada de agente, launcher inbox/Daily, teste de extensão montada, scan de
modelo/API/mail/Queue, mudança de agendamento ou push de registry. Tags de imagens
ativas e contêineres existentes não foram substituídos. Smoke da imagem não prova
correção ponta a ponta do inbox ou Daily. Não foi observada incompatibilidade
bloqueante na cobertura testada; releases flutuantes futuras podem mudar isso.
