<!-- docs/caveman.md -->
# Caveman context compression

## Select and install

Select `ai > opencode` during `chezmoi init`. Caveman is included with OpenCode;
it does not add a picker entry. Its MCP starts disabled. Package mode
plans `@caveman-ai/cli@2.1.0` and Node.js; the CLI installs its pinned
`bin-v2.1.0` companion bundle after checking the signed manifest and checksums.
Installation does not start the proxy or change provider routing.

Every apply ends with a read-only check. With OpenCode selected and no private
route, it prints a red reminder naming `cavemanctl init` and this page. It also
warns when routing is enabled but the proxy does not answer its readiness check.
A route you disabled with `cavemanctl disable` is left alone.

The component installs two pinned upstream skills, `caveman` and
`caveman-review`, with canonical copies and per-skill discovery links. Use
`@caveman` for concise replies and `stop caveman` to stop using that style.
OpenCode also installs the V2 integration plugin. Existing MCP enablement is
preserved on subsequent applies.

## Configure a private route

Initialize one provider route explicitly:

```sh
cavemanctl init --provider example --upstream https://api.example.com
```

The provider must already exist in OpenCode and use an OpenAI-compatible Chat
Completions or Responses API. Add `--wire-dialect anthropic` when the same
upstream also serves Anthropic Messages. Supply the upstream origin before
`/v1`, including any required tenant prefix. Only requests for that origin and
prefix take the route; the path below it is forwarded unchanged. Initialization
creates `~/.caveman/oc2/settings.json` and `proxy-token` with private
permissions. Reruns preserve both files. Edit private settings to change an
existing route.

The proxy defaults to `127.0.0.1:8787` and authenticated compression mode.
`--listen` selects its listening address and `--url` selects the address the
OpenCode server can reach. When OpenCode runs in a container, its loopback is
different from the host's. Use an appropriate host or container-network address
and keep that routing in private settings. A private upstream also needs an
exact `--allow-private-host` entry. The credential used to reach the upstream
remains with the existing OpenCode provider.

### GitHub Copilot

OpenCode's own GitHub Copilot login works through the same named route. As of
OpenCode 2.1.1, Copilot's Claude models use Anthropic Messages and its other
models use Responses or Chat Completions, all on the Copilot API origin:

```sh
cavemanctl init --provider github-copilot --upstream https://api.githubcopilot.com --wire-dialect anthropic
```

Copilot Business and Enterprise accounts can be served from another API host.
Set `upstream` to the origin your OpenCode requests use, or they stay direct.
Without the Anthropic dialect, Messages requests also stay direct: the proxy
would read their usage and compression zones with OpenAI rules. To add the
dialect to an existing route, set `"wire_dialect": "anthropic"` in private
settings and run `cavemanctl restart`; the native service renders its proxy
configuration again on start. For the Compose backend, run `cavemanctl render`
and recreate the container.

## Activate and verify

```sh
cavemanctl enable
cavemanctl status
```

For the default native backend, `enable` starts a systemd user service on Linux
or a launchd user agent on macOS. It marks the private route enabled only after
readiness succeeds.
Services explicitly set `DO_NOT_TRACK=1`, including hosts without managed Zsh.
No system-wide service or lingering setting is installed.

The macOS deployment smoke starts the managed LaunchAgent on an isolated
record-mode loopback route, verifies `cavemanctl status`, then disables and
stops it. This exercises the actual user-service lifecycle rather than only the
raw proxy binary. The service remains a LaunchAgent because it is per-user,
unprivileged, and owns private state under `~/.caveman/oc2`.

Enable the `caveman` MCP in OpenCode's MCP settings, then reload the desired
location. A V2 HTTP request hook routes the selected provider through the proxy
and adds its authentication header. The request body, upstream credential,
other headers, and underlying provider configuration are preserved.
Requests for another origin, outside the upstream prefix, or to unsupported
endpoint paths stay on their original route. That includes native compaction
and token-count endpoints.
The Caveman MCP exposes its compression, recovery, statistics, and TOON tools
directly, with `codemode: false`. Other MCP settings retain their current mode.
Managed `caveman_*` rules allow this family in every agent mode, including
Plan, Explore, Auto, and the demo agent. The shared context-permission plugin
applies them even when proxy routing is disabled. Unrelated rules survive.

Both processes use `~/.caveman/oc2/ccr.db`, so the MCP can recover exactly the
bytes removed by the proxy. The native Caveman enable command is not used:
its installer still assumes particular provider names and legacy configuration
shapes, even though the CLI includes a V2 plugin generator.

Check the native plugin and MCP connection statuses. Then use a synthetic,
tool-heavy task to verify compression and recovery. `cavemanctl stats` shows
local request accounting. Readiness or a configured compression mode alone does
not prove that any request was compressed. Requests without a usable recovery
tool may pass through unchanged, including auxiliary model requests.
Disabling the MCP stops recovery availability but leaves an explicitly enabled
proxy route in place. Use `cavemanctl disable` and reload to restore direct
provider routing.

This route affects the selected OC2 model provider. OpenViking's own recall,
extraction, and embedding connections remain governed by its private server
configuration. The proxy does not rewrite OpenViking's stored transcripts.

The proxy works over HTTP, including streaming Responses. Its recovery-tool
schema consumes context; retrieval adds text and potentially another model
turn. Measure complete tasks, including cached input and recovery overhead,
before treating synthetic reductions as everyday savings.

## Compose backend

For an always-on container host, initialize with `--backend compose` instead.
Set its private `listen` to `0.0.0.0:8787`, `upstream` to the origin reachable
from the container, and `url` to the endpoint reachable by the OC2 server.
Use `cavemanctl render` to generate mode-600 `proxy.json` and `proxy.env` from
the private settings and token. Neither file belongs in a public repository.

Extend the managed service at
`~/.local/share/dotfiles/caveman/compose.yaml` from your own Compose stack.
Set `CAVEMAN_STATE_DIR` to the absolute private state directory and
`CAVEMAN_UID`/`CAVEMAN_GID` to its owner's IDs. `CAVEMAN_BIND` defaults to
loopback and `CAVEMAN_PORT` to 8787. Select the stack's network in the private
extension. The same state directory is mounted at the same absolute path so
native MCP processes can recover originals written by the container.

The service pins the upstream multi-architecture `bin-v2.1.0` image by digest,
runs without Linux capabilities, and uses `restart: unless-stopped`.
It needs no user-systemd lingering. The upstream image documents a Go-only code
compressor; a Linux host can mount its signature-verified native bundle
read-only and override the entrypoint to use the full code compressor. Keep
the binary release aligned with the image and recreate the container when
updating it. Logs, JSON, and other supported text formats do not require that
override.

Once the stack is running, `cavemanctl enable` verifies readiness and marks
OC2 routing enabled. With `backend: compose`, it does not start a user service;
Compose owns container startup, shutdown, and restarts. Keep one proxy writer
per state directory. Stop the native service before moving the same state to
Compose.

## Disable and recover

```sh
cavemanctl disable
```

Reload every active OpenCode location using the integration. Removing its
transforms restores the provider's underlying configuration. After those
locations use direct routing, stop a native proxy:

```sh
cavemanctl stop
```

The separate steps allow active requests to finish before the listener stops.
For the Compose backend, stop the proxy service through its owning stack instead.
Disable and reload before deselecting OpenCode. Chezmoi does not remove
private settings, credentials, installed companions, or recovery originals.
Changing private enabled state survives subsequent applies.

## Ownership

Chezmoi owns `cavemanctl`, the platform user-service definition, the V2 plugin,
and pinned skill files. Caveman and the operator own `~/.caveman` and
`~/.caveman-cloud`, including telemetry preference, credentials, indexes,
recovery originals, private routes, and generated proxy configuration.
Back up this private state according to the sensitivity of the tool output.

References: [Caveman](https://github.com/JuliusBrussee/caveman),
[V2 provider configuration](https://opencode.ai/v2/docs/providers), and
[V2 MCP configuration](https://opencode.ai/v2/docs/mcp-servers).
