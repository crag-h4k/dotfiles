<!-- docs/openviking.md -->
# OpenViking local memory

## Table of Contents

- [Select and install](#select-and-install)
- [Configuration ownership](#configuration-ownership)
- [Choose providers](#choose-providers)
- [Initialize and validate](#initialize-and-validate)
- [Start the user service](#start-the-user-service)
- [Enable OpenCode capture](#enable-opencode-capture)
- [OpenCode permissions](#opencode-permissions)
- [Measure the trial](#measure-the-trial)
- [Storage and recovery](#storage-and-recovery)

## Select and install

Select `ai > openviking` during `chezmoi init`. It is off by default and does
not require OpenCode. Selecting both `openviking` and `opencode` registers the
official `@openviking/opencode-plugin` package in the managed plugin section.

Package mode previews OpenViking `0.4.23`, Python, and uv where needed. The
installer creates an isolated, wheel-only Python environment, verifies its
native engine and required imports, then switches the stable runtime pointer.
Previous environments remain available. It does not download Ollama models,
initialize private model settings, log into providers, or start services.

The OpenCode integration pins the official plugin at `2026.10.7` for hooks only.
Native MCP and native skill discovery provide the tools and three upstream
skills. No copy of the plugin is patched or forked.

The native runtime works on macOS arm64 and Debian arm64/x86_64. Keep Ollama
native on a Mac to use Apple GPU acceleration. Docker Desktop on macOS does not
provide GPU acceleration for Ollama; containerizing OpenViking alone would still
require a route back to the native Ollama service.

## Configuration ownership

Dotfiles installs `openvikingctl`, platform user-service definitions, and
read-only starter profiles under `~/.local/share/dotfiles/openviking/`.
It does not manage these private files:

- `~/.openviking/ov.conf`: server, storage, and model configuration.
- `~/.openviking/ovcli.conf`: client credential and plugin settings.
- `~/.openviking/service.env`: optional `KEY=value` environment settings.
- `~/.openviking/data/`: database, indexes, and captured transcripts.
- `~/.config/litellm/github_copilot/`: LiteLLM's provider credentials.

The installer owns `~/.openviking/runtime.json` only to record its local runtime
location. `OPENVIKING_INSTALL_ROOT` can select a different installation root;
subsequent package plans reuse that location record. Runtime state is ignored
by chezmoi.

Each host owns its live configuration. A laptop can use Copilot extraction and
local embeddings while a VM uses an approved remote endpoint. Updating dotfiles
updates starter examples without replacing either host's settings. The private
files and memory database are not synchronized between machines.

## Choose providers

Extraction and embeddings are independent choices. Starter profiles include:

- `copilot-ollama`: Copilot extraction through LiteLLM, local Nomic embeddings.
- `ollama`: local Qwen extraction and local Nomic embeddings.
- `openai`: OpenAI API-key extraction and embeddings.
- `codex-ollama`: native Codex OAuth extraction and local Nomic embeddings.

These model names are starting points, not evidence of access on your account.
Verify the configured models before capturing normal sessions. OpenViking does
not inherit OpenCode's authentication. LiteLLM manages a separate Copilot device
login; OpenViking's native Codex route can import Codex auth during its setup.
An OpenAI API key and a ChatGPT/Codex subscription are separate authentication
and billing paths.

The laptop-oriented local embedding profile uses `nomic-embed-text:v1.5`, with
768-dimensional vectors and one concurrent embedding request. Its model download
is 274 MB; that is not a measurement of loaded RAM. The local extraction example
uses `qwen3.5:4b`, one concurrent request, a 16K context window, and thinking off.
Measure its working memory and energy use before keeping it active on battery.

Changing an embedding model or its vector space requires a new workspace or a
deliberate reindex. Keep embeddings fixed when comparing extraction providers.
There is no configured cloud fallback in the local profile.

## Initialize and validate

Initialize a private copy once:

```sh
~/.local/bin/openvikingctl init --profile copilot-ollama
```

This preserves existing configuration. A new server config receives a random
root API key; no key is printed. New private files have mode 600. Edit `ov.conf`
for this host after initialization. The service runs from the config directory,
so the example `./data` workspace resolves to `~/.openviking/data`.

Authenticate Copilot from your own foreground terminal:

```sh
~/.local/bin/openvikingctl auth-copilot
```

Complete the displayed device login before starting a background service. Keep
provider credentials out of source, shell history, and shared logs. If a provider
needs environment variables, put quoted `KEY=value` assignments in the private
`service.env` file and give it mode 600. The loader does not execute shell code.
Existing exported variables take precedence.

Download only the Ollama models you chose. For the initial profile:

```sh
ollama pull nomic-embed-text:v1.5
```

Validate the installation and make small synthetic model probes:

```sh
~/.local/bin/openvikingctl doctor
~/.local/bin/openvikingctl probe-models
```

The upstream `0.4.23` doctor incorrectly reports a missing VLM API key for the
Copilot LiteLLM route, even though runtime authentication belongs to LiteLLM.
Do not add a fake key to make that check pass. Inspect every doctor result;
`probe-models` verifies real embedding dimensions and a real extraction response.
It prints timings and dimensions, not credentials or returned model text.
The probes do not establish memory-capture or recall quality.

## Start the user service

```sh
~/.local/bin/openvikingctl enable
~/.local/bin/openvikingctl bootstrap-client
~/.local/bin/openvikingctl status
```

`enable` uses a launchd user agent on macOS or `systemctl --user` on Debian.
No root service is created. The initial launchd definition is disabled until
explicitly enabled; the systemd unit is not enabled by apply. A Debian session
needs a working user systemd manager. Do not enable lingering or change system
services as an installation side effect.

The listener is forced to `127.0.0.1`; a non-loopback configured host is rejected.
API-key authentication is required. The root key administers accounts only.
`bootstrap-client` creates a separate USER data credential in private
`ovcli.conf`. It preserves an existing client key and does not print new keys.
If an earlier bootstrap partially created accounts or users, inspect that
private server's state rather than automatically rotating credentials.

After changing private configuration, validate it again and run
`openvikingctl restart`. For shutdown, use `openvikingctl stop`; this disables
future automatic startup too. Stop the service before deselecting the component.
Deselecting does not delete private configuration, installed releases, or memory.

## Enable OpenCode capture

The starter sets `plugin.opencode.mcpEnabled=false`. This skips the plugin's
bundled MCP/skill registration, which calls the unsupported `SkillEditor.source`
API in OpenCode `2.0.24`. It does not disable automatic capture or recall.
The OpenViking component installs the three unmodified upstream skills through
native discovery: `openviking-memory`, `openviking-skills`, and
`ov-experience-memory`. They use the existing canonical store and per-entry
compatibility links.

Prepare the authenticated native MCP connection:

```sh
~/.local/bin/openvikingctl mcp-config
```

This command writes a private mode-600 `mcp-user-key` and prints a V2 connection
fragment using `{file:...}` substitution, never the key itself. Review and merge
only its `mcp.servers.openviking` entry into your private global OpenCode config.
Keep unrelated servers and comments. The read-only `opencode-mcp.json` starter
shows the portable shape. Live MCP routing and credentials remain unmanaged.

The server's Streamable HTTP endpoint uses the same `127.0.0.1:1933` listener
and exposes its native tool catalog, including memory, resources, skills,
filesystem, watches, and account/ACL tools. API-key mode uses `oauth: false`;
`codemode: false` keeps the tools directly available to the agent. Tool
registration does not grant permission to modify or delete data.

Verify server readiness and authenticated client access before opening a new
OpenCode session:

```sh
curl --fail http://127.0.0.1:1933/ready
~/.local/bin/openvikingctl cli -- ls viking://
```

Readiness alone does not validate the client key. The filesystem listing uses
an authenticated tenant-data endpoint.

After OpenCode reloads the reviewed connection, run:

```sh
~/.local/bin/openvikingctl check-opencode
```

The check requires an active official plugin, a connected native MCP server,
and all three discovered skills. It deliberately fails if registrations are
missing. Registration is not proof of capture and recall; perform the synthetic
cross-session, compaction, and restart test below too.

The upstream plugin provides automatic recall and turn capture, including
capture before compaction. The starter disables automatic repository indexing,
query expansion, and recall compression to keep the initial trial focused on
memory and avoid extra model calls. Normal capture includes tool output.

The OpenCode starter sets `commitKeepRecentCount=0`. At commit boundaries,
OpenViking archives the captured messages instead of retaining a raw tail that
can prevent short sessions from producing memories. OpenCode keeps its own
transcript. The upstream 20K-token threshold remains unchanged, so this does not
request extraction after every turn. Set a positive retention count in private
`plugin.opencode` settings if raw-tail continuity matters more than prompt
cross-session availability. Reload OpenCode locations after changing this value;
the plugin reads its configuration when its runtime starts.

Start with synthetic conversations. Check that a fresh session in another
project recalls a decision and its rationale, then repeat after compaction and
restart. Only then enable ordinary work. Local storage does not keep model
processing local when extraction or embeddings use a remote provider. Confirm
the selected route is permitted for the content you will capture.

A local `-openviking` control after the managed plugin section disables the
plugin. To stop capture while retaining recall, set `plugin.autoCapture` to
`false` in private `ovcli.conf` and reload OpenCode. Existing Markdown memory
files are neither imported nor modified automatically.

After an OpenCode or OpenViking update, repeat the registration and synthetic
checks before assuming memory still works. Native MCP/discovery reduce plugin
API coupling, but they cannot guarantee compatibility with an untested future
release. Keep the last validated runtime recoverable and review plugin pin
updates rather than loading a floating npm release.

## OpenCode permissions

The marked global permission block and managed local plugin
`plugins/openviking-permissions.js` allow
`openviking_*` MCP actions and the OpenViking skills in every registered agent.
The global block follows generic catch-all rules, and the local transform adds
the same exceptions to agent defaults. Plan, Explore, Auto, and custom
read-only agents can use memory without enabling unrelated writes.
New agents receive the same exceptions when the registry is rebuilt.

The skill exceptions cover `openviking-*` and `ov-experience-memory`. These
rules do not allow shell lifecycle commands, Git operations, filesystem edits,
or access to protected credential files. OpenViking's server-side account/ACL
checks and organization-level hard permission policies still apply. Destructive
operations still need any confirmation required by the agent's instructions.

The registration check uses the native plugin source/state record and writes
CLI output to a private temporary file before parsing. That avoids losing large
skill registries when the CLI exits before pipe output drains. A connected MCP
server does not make a failed capture plugin count as active.

Exact package pins can still be blocked by a locally configured npm release-age
policy. This integration does not require an age gate. Review the effective npm
configuration when the registry reports that a pinned version exists but npm
rejects its publication date. Preserve the exact pin, registry integrity checks,
and matching OpenCode SDK runtime rather than substituting an unreviewed release.

## Measure the trial

Use the same synthetic corpus and query set for each provider comparison. Record
the model names, versions, context limits, concurrency, and whether the model
was already loaded. Compare cold requests separately from warm requests.

OpenViking's request telemetry can separate intent analysis, query embedding,
vector retrieval, and extraction timing. Request `telemetry: true` on supported
HTTP operations; missing fields are unavailable measurements, not zero. Session
commit timing covers submission, so wait for its returned task before claiming
that extraction finished.

Measure:

- Retrieval p50/p95 latency and whether expected memories were returned.
- Capture failures, extraction errors, and queue backlog.
- OpenViking and loaded Ollama memory during comparable workloads.
- Provider token/request consumption.
- Battery discharge during similar editing sessions with capture off and on.

Use `ollama ps` for loaded-model memory and GPU placement. Ollama normally unloads
idle models after five minutes. Avoid an indefinite keep-alive setting for the
trial, and run the larger local extraction comparison on AC power first.
Do not infer battery impact from a plugged-in latency benchmark.

For a repeatable retrieval check, first capture a synthetic conversation that
chooses marker `drake-913` and disables automatic repository indexing to
`isolate memory performance`. Wait for extraction, then run:

```sh
python3 scripts/benchmark-openviking.py \
  --cases tests/fixtures/openviking/queries.json --rounds 5
```

The report contains request timings, HTTP failures, and expected-marker hit
rates. It records neither queries nor retrieved content. This measures
`search.find`, not the plugin's full prompt-time recall path. The first request
is reported separately; call it cold only if the model was unloaded beforehand.
Use the same corpus and queries when comparing providers. Save reports privately
outside this repository if you want a multi-day history.

## Storage and recovery

Keep the private workspace on protected storage. It contains source transcripts,
tool output, and derived memories. Use private backups; chezmoi does not back up
or synchronize this database. Do not share one live embedded workspace between
multiple server processes.

If a new Python environment fails import checks, the old runtime pointer remains
unchanged. A previous release can be selected again after stopping the service.
Back up the workspace before upgrades that might change its data format; an old
Python environment alone does not reverse a database migration.

References:

- [OpenViking OpenCode integration](https://docs.openviking.ai/en/agent-integrations/10-opencode).
- [OpenCode V2 MCP configuration](https://opencode.ai/v2/docs/mcp-servers).
- [OpenCode V2 native skill discovery](https://opencode.ai/v2/docs/skills).
- [Server deployment](https://docs.openviking.ai/en/guides/03-deployment).
- [Provider configuration](https://docs.openviking.ai/en/guides/01-configuration).
- [API-key authentication](https://docs.openviking.ai/en/guides/04-authentication).
- [Operation telemetry](https://docs.openviking.ai/en/guides/07-operation-telemetry).
- [LiteLLM Copilot authentication](https://docs.litellm.ai/docs/providers/github_copilot).
- [Ollama memory and GPU behavior](https://docs.ollama.com/faq).
