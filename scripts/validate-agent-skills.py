# scripts/validate-agent-skills.py
"""Validate the public, offline contract for cross-harness agent skills."""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from urllib.parse import urlsplit


REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_IDS = ("humanizer", "unslop-code", "unslop-text", "unslop-ui")
AI_FEATURES = (
    "claude_hooks",
    "codex_hooks",
    "statusline",
    "opencode",
    "copilot",
    "codecompanion",
)
ALLOWED_URL_HOSTS = {
    "agentskills.io",
    "code.claude.com",
    "developers.openai.com",
    "docs.github.com",
    "github.com",
    "opencode.ai",
    "raw.githubusercontent.com",
    "www.chezmoi.io",
}
PUBLIC_TEXT_FILES = (
    "docs/agent-skills.md",
    "home/dot_local/share/agent-skills/readonly_PROVENANCE.md",
    "home/dot_local/share/agent-skills/humanizer/readonly_SKILL.md",
    "home/dot_local/share/agent-skills/humanizer/agents/readonly_openai.yaml",
    "home/dot_config/opencode/commands/humanize.md",
    "home/dot_config/opencode/commands/unslop.md",
)
EXPECTED_EXTERNALS = {
    ".local/share/agent-skills/unslop-code/SKILL.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-code/skill/SKILL.md",
        "118b4e3a21630da847a7be1c9a27f5c47f027efb2c189ea8d47299f1566b5724",
    ),
    ".local/share/agent-skills/unslop-code/references/fitting-the-codebase.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-code/skill/references/fitting-the-codebase.md",
        "c707ee0c655fafd6d97831318ff9affdc2279d9c446cdcf9dad5caba20c87b2b",
    ),
    ".local/share/agent-skills/unslop-code/references/tells.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-code/skill/references/tells.md",
        "22983d016fc83cd5cab6388c1951caca2cdcf4ad5ec223b6b44988d86aed9321",
    ),
    ".local/share/agent-skills/unslop-code/scripts/unslop_code_scan.py": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-code/skill/scripts/unslop_code_scan.py",
        "9c00940691034a1b7bae8a97e46c5e33073f67b66d42fb4468e18641e1edccc8",
    ),
    ".local/share/agent-skills/unslop-code/LICENSE": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-code/LICENSE",
        "cf2ad096a80ad090167e532c6bc2a01880ca5811595fd657e7fd88b6071ab84a",
    ),
    ".local/share/agent-skills/unslop-text/SKILL.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-text/skill/SKILL.md",
        "5e6dc683b8604110d0d6953b9499d069939c7c03f2aecf55ce4f94b664320737",
    ),
    ".local/share/agent-skills/unslop-text/references/tells.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-text/skill/references/tells.md",
        "3346b94c4804555f7c132de6904fe049d866ca92e4c1218ea46e1de3432b64c6",
    ),
    ".local/share/agent-skills/unslop-text/references/writing-with-intent.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-text/skill/references/writing-with-intent.md",
        "efdf1480ead5e1d061d071d052685b9fc14a55053dab27125c4c0494fb9381f3",
    ),
    ".local/share/agent-skills/unslop-text/scripts/unslop_text_scan.py": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/unslop-ai-text/skill/scripts/unslop_text_scan.py",
        "e494196e8e20fa3d44b9ff96c094b0deef9d46173fc4cd9ab7957ab6c8f05dea",
    ),
    ".local/share/agent-skills/unslop-text/LICENSE": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/LICENSE",
        "9ef1e40441ba739df595abddf19002d81c59fe25f4288ab0aef6c1cc3e17ea80",
    ),
    ".local/share/agent-skills/unslop-ui/SKILL.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/skill/SKILL.md",
        "e3f2f97441f8faffab7421dfef43f145155e1fbc06edc27813c04929174f6450",
    ),
    ".local/share/agent-skills/unslop-ui/references/choosing-a-look.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/skill/references/choosing-a-look.md",
        "1c83902d1bde857cfc33da43e6ae8683574a6734e821892565dce53cbcef0da4",
    ),
    ".local/share/agent-skills/unslop-ui/references/tells.md": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/skill/references/tells.md",
        "032176c6d9b2951769abc4f7ff618ff0219f2d052ba2599a6c1c27a827d72856",
    ),
    ".local/share/agent-skills/unslop-ui/scripts/devibe_scan.py": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/skill/scripts/devibe_scan.py",
        "6e516bea614831349525b608549257f97723315437cdbf52436f97213db48090",
    ),
    ".local/share/agent-skills/unslop-ui/LICENSE": (
        "https://raw.githubusercontent.com/JCarterJohnson/vibecoded-design-tells/f7c4aefc2c797a66e55b49354a93917ab60d33ac/LICENSE",
        "9ef1e40441ba739df595abddf19002d81c59fe25f4288ab0aef6c1cc3e17ea80",
    ),
    ".local/share/agent-skills/humanizer/upstream/SKILL.md": (
        "https://raw.githubusercontent.com/blader/humanizer/9862685f575c65a8247f90369951df1b3416e3d6/SKILL.md",
        "e8269e236bed06ed0fe4824c274112e54950b0cb46b0bafe5e1576ef7c9f93d5",
    ),
    ".local/share/agent-skills/humanizer/upstream/agents/openai.yaml": (
        "https://raw.githubusercontent.com/blader/humanizer/9862685f575c65a8247f90369951df1b3416e3d6/agents/openai.yaml",
        "9d87ff83149a04f86a372948b8ee35fa249de20923867bbc2a49304290aad736",
    ),
    ".local/share/agent-skills/humanizer/upstream/LICENSE": (
        "https://raw.githubusercontent.com/blader/humanizer/9862685f575c65a8247f90369951df1b3416e3d6/LICENSE",
        "4ac4810254ab36d45419141aeb8e69bf50652cfafe5b2dab947d06d44e5cbf96",
    ),
}
EXPECTED_GATED_TARGETS = {
    ".local/share/agent-skills/PROVENANCE.md",
    *(f".local/share/agent-skills/{skill_id}" for skill_id in SKILL_IDS),
    *(f".claude/skills/{skill_id}" for skill_id in SKILL_IDS),
    *(f".agents/skills/{skill_id}" for skill_id in SKILL_IDS),
    ".config/opencode/commands/humanize.md",
    ".config/opencode/commands/unslop.md",
}


def scan_public_text(label: str, text: str) -> list[str]:
    """Return public-boundary violations in one authored text file."""
    checks = (
        (
            "private-key material",
            re.compile(r"BEGIN [A-Z ]*PRIVATE KEY", re.IGNORECASE),
        ),
        (
            "cloud access-key material",
            re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
        ),
        (
            "service token material",
            re.compile(r"\b(?:gh[oprs]|xox[baprs])_[A-Za-z0-9]{10,}\b"),
        ),
        (
            "model API-key material",
            re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),
        ),
        (
            "credential assignment",
            re.compile(
                r"\b(?:api[_-]?key|secret|token|passwd|password)\s*[:=]\s*"
                r"[\"']?(?!example|placeholder|redacted)[A-Za-z0-9_./+=-]{8,}",
                re.IGNORECASE,
            ),
        ),
        (
            "real home path",
            re.compile(
                r"(?<![A-Za-z0-9._-])/(?:Users|home)/"
                r"(?!example(?:/|\b)|runner(?:/|\b)|user(?:/|\b))"
                r"[A-Za-z][A-Za-z0-9_.-]*"
            ),
        ),
        ("work-tree shorthand", re.compile(r"(?:^|\s)~/(?:work|workspace)(?:/|\b)")),
        (
            "personal or corporate email",
            re.compile(
                r"\b[A-Za-z0-9._%+-]+@"
                r"(?!(?:example\.com|example\.invalid|users\.noreply\.github\.com)\b)"
                r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"
            ),
        ),
        (
            "corporate name",
            re.compile(r"\b[A-Z][A-Za-z0-9]+Corp(?:oration)?\b"),
        ),
        (
            "internal codename declaration",
            re.compile(r"\b(?:internal[- ]name|project[- ]codename)\s*[:=]", re.IGNORECASE),
        ),
        (
            "private endpoint",
            re.compile(r"\b(?:[A-Za-z0-9-]+\.)+(?:corp|internal)(?:\.[A-Za-z0-9-]+)+\b", re.IGNORECASE),
        ),
        (
            "private MCP configuration",
            re.compile(r"^\s*(?:mcp|mcpServers)\s*[:=]", re.IGNORECASE | re.MULTILINE),
        ),
        (
            "Jira-style identifier",
            re.compile(r"\b(?!(?:SHA|UTF|RFC|ISO)-)[A-Z][A-Z0-9]{2,}-[0-9]+\b"),
        ),
        (
            "UUID",
            re.compile(
                r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
                r"[0-9a-f]{4}-[0-9a-f]{12}\b",
                re.IGNORECASE,
            ),
        ),
    )
    errors = [f"{label}: contains {name}" for name, pattern in checks if pattern.search(text)]

    for raw_url in re.findall(r"https?://[^\s<>\])}\"']+", text):
        url = raw_url.rstrip(".,;:")
        parsed = urlsplit(url)
        host = (parsed.hostname or "").lower()
        if host not in ALLOWED_URL_HOSTS:
            errors.append(f"{label}: URL uses unexpected host {host or '<missing>'}")
            continue
        if re.search(r"/(?:main|master|latest)(?:/|$)", parsed.path, re.IGNORECASE):
            errors.append(f"{label}: URL uses a mutable ref: {url}")
        if host == "raw.githubusercontent.com":
            parts = parsed.path.strip("/").split("/")
            if len(parts) < 4 or not re.fullmatch(r"[0-9a-f]{40}", parts[2]):
                errors.append(f"{label}: raw GitHub URL lacks an exact commit: {url}")
        if host == "github.com" and "/tree/" in parsed.path:
            ref = parsed.path.split("/tree/", maxsplit=1)[1].split("/", maxsplit=1)[0]
            if not re.fullmatch(r"[0-9a-f]{40}", ref):
                errors.append(f"{label}: GitHub tree URL lacks an exact commit: {url}")
    return errors


def render_template(root: Path, source: str, enabled_features: set[str]) -> str:
    """Render a chezmoi template with a complete synthetic AI component table."""
    lines = [
        '[data]\ninstallMode = "configs"',
        "[data.components]",
        "zsh = false",
        "tmux = false",
        "neovim = false",
        "[data.components.ai]",
    ]
    lines.extend(
        f"{feature} = {str(feature in enabled_features).lower()}"
        for feature in AI_FEATURES
    )
    lines.extend(
        (
            "[data.components.git]",
            "config = false",
            "personal = false",
            "ignore_global = false",
            "[data.components.terminal]",
            "ghostty = false",
            "iterm2 = false",
        )
    )

    with tempfile.TemporaryDirectory() as temp_dir:
        config = Path(temp_dir) / "chezmoi.toml"
        config.write_text("\n".join(lines) + "\n", encoding="utf-8")
        result = subprocess.run(
            [
                "chezmoi",
                "execute-template",
                "--source",
                str(root),
                "--config",
                str(config),
            ],
            input=(root / source).read_text(encoding="utf-8"),
            text=True,
            capture_output=True,
            check=False,
        )
    if result.returncode:
        raise RuntimeError(f"could not render {source}: {result.stderr.strip()}")
    return result.stdout


def validate_external_contract(root: Path) -> list[str]:
    """Check exact pins, checksums, readonly mode, and AI gating."""
    errors: list[str] = []
    disabled = tomllib.loads(render_template(root, "home/.chezmoiexternal.toml", set()))
    leaked = sorted(key for key in disabled if key.startswith(".local/share/agent-skills/"))
    if leaked:
        errors.append(f"disabled AI rendered agent-skill externals: {', '.join(leaked)}")

    for feature in AI_FEATURES:
        rendered = tomllib.loads(
            render_template(root, "home/.chezmoiexternal.toml", {feature})
        )
        actual = {
            key: value
            for key, value in rendered.items()
            if key.startswith(".local/share/agent-skills/")
        }
        if set(actual) != set(EXPECTED_EXTERNALS):
            errors.append(f"AI feature {feature} rendered an unexpected external file set")
            continue
        for target, (expected_url, expected_sha256) in EXPECTED_EXTERNALS.items():
            spec = actual[target]
            checksum = spec.get("checksum", {}).get("sha256")
            if spec.get("type") != "file":
                errors.append(f"{target}: external type must be file")
            if spec.get("url") != expected_url:
                errors.append(f"{target}: URL does not match its audited immutable pin")
            if checksum != expected_sha256:
                errors.append(f"{target}: SHA-256 does not match its audited value")
            if spec.get("readonly") is not True:
                errors.append(f"{target}: external must be read-only")
            if spec.get("executable", False) is not False:
                errors.append(f"{target}: external must be non-executable")
            if "refreshPeriod" in spec or "urls" in spec:
                errors.append(f"{target}: external must not have mutable refresh or fallback URLs")
    return errors


def validate_ignore_contract(root: Path) -> list[str]:
    """Check that every AI sub-feature controls the same per-path asset set."""
    errors: list[str] = []
    disabled = set(render_template(root, "home/.chezmoiignore", set()).splitlines())
    missing = EXPECTED_GATED_TARGETS - disabled
    if missing:
        errors.append(f"disabled AI fails to ignore: {', '.join(sorted(missing))}")

    forbidden_whole_dirs = {".claude/skills", ".agents/skills"}
    if disabled & forbidden_whole_dirs:
        errors.append("AI gate ignores a whole harness skills directory")

    for feature in AI_FEATURES:
        enabled = set(
            render_template(root, "home/.chezmoiignore", {feature}).splitlines()
        )
        still_ignored = EXPECTED_GATED_TARGETS & enabled
        if still_ignored:
            errors.append(
                f"AI feature {feature} still ignores: {', '.join(sorted(still_ignored))}"
            )
    return errors


def validate_layout(root: Path) -> list[str]:
    """Check the canonical store and per-skill compatibility links."""
    errors: list[str] = []
    expected_links = {
        root / f"home/dot_{harness}/skills/symlink_{skill_id}"
        for harness in ("claude", "agents")
        for skill_id in SKILL_IDS
    }
    actual_links = {
        path
        for harness in ("claude", "agents")
        for path in (root / f"home/dot_{harness}/skills").glob("*")
        if path.is_file()
    }
    if actual_links != expected_links:
        unexpected = sorted(str(path.relative_to(root)) for path in actual_links - expected_links)
        missing = sorted(str(path.relative_to(root)) for path in expected_links - actual_links)
        if unexpected:
            errors.append(f"unexpected harness skill source files: {', '.join(unexpected)}")
        if missing:
            errors.append(f"missing harness skill source files: {', '.join(missing)}")

    effective_ids: set[str] = set()
    for link_source in expected_links & actual_links:
        skill_id = link_source.name.removeprefix("symlink_")
        expected_target = f"../../.local/share/agent-skills/{skill_id}"
        if link_source.read_text(encoding="utf-8").strip() != expected_target:
            errors.append(f"{link_source.relative_to(root)}: unexpected symlink target")
        effective_ids.add(skill_id)
    if effective_ids != set(SKILL_IDS):
        errors.append("compatibility roots do not resolve to one effective ID per skill")

    whole_directory_sources = (
        "home/dot_claude/symlink_skills",
        "home/dot_agents/symlink_skills",
        "home/dot_codex/symlink_skills",
        "home/dot_config/opencode/symlink_skills",
    )
    for source in whole_directory_sources:
        if (root / source).exists():
            errors.append(f"{source}: whole-directory skill symlinks are forbidden")

    unexpected_roots = (
        "home/dot_copilot/skills",
        "home/dot_codex/skills",
        "home/dot_config/opencode/skills",
    )
    for source in unexpected_roots:
        if (root / source).exists():
            errors.append(f"{source}: unexpected harness-specific skill copy")

    canonical_root = root / "home/dot_local/share/agent-skills"
    expected_managed = {
        canonical_root / "readonly_PROVENANCE.md",
        canonical_root / "humanizer/readonly_SKILL.md",
        canonical_root / "humanizer/agents/readonly_openai.yaml",
    }
    actual_managed = {path for path in canonical_root.rglob("*") if path.is_file()}
    if actual_managed != expected_managed:
        errors.append("canonical source contains unexpected managed files")

    return errors


def validate_component_contract(root: Path) -> list[str]:
    """Ensure writing-quality assets stay an automatic child of AI."""
    errors: list[str] = []
    forbidden_toggle = re.compile(r"writing[-_]?quality", re.IGNORECASE)
    for relative in (
        "home/.chezmoi.toml.tmpl",
        "home/.chezmoiscripts/run_once_after_00-install.sh.tmpl",
        "scripts/install.sh",
        "scripts/package-plan.sh",
    ):
        path = root / relative
        if not path.is_file():
            errors.append(f"{relative}: required component file is missing")
        elif forbidden_toggle.search(path.read_text(encoding="utf-8")):
            errors.append(f"{relative}: writing quality must not have a separate toggle")
    return errors


def validate_invocation_policy(root: Path) -> list[str]:
    """Check Humanizer manual-only policy and command safety."""
    errors: list[str] = []
    adapter = (
        root / "home/dot_local/share/agent-skills/humanizer/readonly_SKILL.md"
    ).read_text(encoding="utf-8")
    codex = (
        root
        / "home/dot_local/share/agent-skills/humanizer/agents/readonly_openai.yaml"
    ).read_text(encoding="utf-8")
    required_adapter_lines = (
        "user-invocable: true",
        "disable-model-invocation: true",
        "opencode/autoinvoke: false",
    )
    for line in required_adapter_lines:
        if line not in adapter:
            errors.append(f"humanizer adapter is missing {line}")
    if "allowed-tools:" in adapter:
        errors.append("humanizer adapter must not pre-approve tools")
    if "allow_implicit_invocation: false" not in codex:
        errors.append("humanizer Codex metadata allows implicit invocation")
    if "dependencies:" in codex or "mcp" in codex.lower():
        errors.append("humanizer Codex metadata must not declare runtime dependencies")

    humanize = (
        root / "home/dot_config/opencode/commands/humanize.md"
    ).read_text(encoding="utf-8")
    humanizer_position = humanize.find("Load `humanizer`")
    unslop_position = humanize.find("load `unslop-text`")
    if humanizer_position < 0 or unslop_position < humanizer_position:
        errors.append("humanize command does not run Humanizer before unslop-text")
    for command in ("humanize", "unslop"):
        text = (root / f"home/dot_config/opencode/commands/{command}.md").read_text(
            encoding="utf-8"
        )
        if re.search(r"!`", text):
            errors.append(f"OpenCode /{command} command contains a shell block")
    return errors


def validate_public_text(root: Path) -> list[str]:
    """Scan the authored public surface for identity and trust-boundary leaks."""
    errors: list[str] = []
    for relative in PUBLIC_TEXT_FILES:
        path = root / relative
        if not path.is_file():
            errors.append(f"{relative}: required public file is missing")
            continue
        errors.extend(scan_public_text(relative, path.read_text(encoding="utf-8")))
    return errors


def validate_repository(root: Path = REPO_ROOT) -> list[str]:
    """Run every offline agent-skill validation."""
    errors: list[str] = []
    if not (root / ".chezmoiroot").is_file():
        return [f"{root}: not a dotfiles repository root"]
    for validator in (
        validate_external_contract,
        validate_ignore_contract,
        validate_layout,
        validate_component_contract,
        validate_invocation_policy,
        validate_public_text,
    ):
        try:
            errors.extend(validator(root))
        except (OSError, RuntimeError, subprocess.SubprocessError, tomllib.TOMLDecodeError) as error:
            errors.append(f"{validator.__name__}: {error}")
    return errors


def main() -> int:
    errors = validate_repository()
    if errors:
        for error in errors:
            print(f"validate-agent-skills: {error}", file=sys.stderr)
        return 1
    print(
        "validate-agent-skills: OK - exact pins, AI gates, per-skill links, "
        "manual Humanizer policy, and public boundary"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
