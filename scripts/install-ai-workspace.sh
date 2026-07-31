#!/usr/bin/env bash
# Provision one authored AI workspace for Claude Code and Codex without owning
# either tool's complete extension directories or runtime stores.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$REPO_DIR/ai"

INSTALL_AI_SHARED_WORKSPACE="${INSTALL_AI_SHARED_WORKSPACE:-false}"
INSTALL_AI_CLAUDE_HOOKS="${INSTALL_AI_CLAUDE_HOOKS:-false}"
INSTALL_AI_CODEX_HOOKS="${INSTALL_AI_CODEX_HOOKS:-false}"
AI_OVERLAY_SYNC_ONLY="${AI_OVERLAY_SYNC_ONLY:-false}"

ai_dir="${DOTFILES_AI_DIR:-$HOME/ai}"
case "$ai_dir" in
    "~") ai_dir="$HOME" ;;
    \~/*) ai_dir="$HOME/${ai_dir#\~/}" ;;
esac
case "$ai_dir" in
    /*) ;;
    *) printf 'install-ai-workspace: DOTFILES_AI_DIR must be absolute or start with ~/: %s\n' "$ai_dir" >&2; exit 1 ;;
esac

backup_stamp="$(date +%Y%m%dT%H%M%S)"
backup_dir="$ai_dir/.dotfiles-backup/$backup_stamp"
backup_count=0
conflict_count=0
overlay_config="$ai_dir/overlays.conf"
overlay_state="$ai_dir/.overlay-links"

path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

backup_path() {
    local path="$1" rel destination
    path_exists "$path" || return 0
    case "$path" in
        "$HOME"/*) rel="home/${path#"$HOME/"}" ;;
        "$ai_dir"/*) rel="ai/${path#"$ai_dir/"}" ;;
        *) rel="other/${path#/}" ;;
    esac
    destination="$backup_dir/$rel"
    mkdir -p "$(dirname "$destination")"
    mv "$path" "$destination"
    backup_count=$((backup_count + 1))
}

# Singleton files have no meaningful per-entry merge. Preserve an existing
# value before installing the common global instructions.
link_singleton() {
    local source="$1" destination="$2"
    if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
        return 0
    fi
    path_exists "$destination" && backup_path "$destination"
    mkdir -p "$(dirname "$destination")"
    ln -s "$source" "$destination"
}

# Collections use a non-destructive overlay. A same-named native or private
# entry wins; dotfiles never moves or replaces it.
link_entry() {
    local source="$1" destination="$2"
    if [[ "$source" == "$destination" ]]; then
        return 0
    fi
    if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
        return 0
    fi
    if [[ -L "$destination" && ! -e "$destination" ]]; then
        unlink "$destination"
    elif path_exists "$destination"; then
        printf 'WARN: ai overlay collision; keeping existing entry: %s\n' "$destination" >&2
        conflict_count=$((conflict_count + 1))
        return 0
    fi
    mkdir -p "$(dirname "$destination")"
    ln -s "$source" "$destination"
}

link_directory_entries() {
    local source_dir="$1" destination_dir="$2" source name
    [[ -d "$source_dir" ]] || return 0
    mkdir -p "$destination_dir"
    shopt -s dotglob nullglob
    for source in "$source_dir"/*; do
        name="${source##*/}"
        link_entry "$source" "$destination_dir/$name"
    done
    shopt -u dotglob nullglob
}

unlink_recorded_overlays() {
    local destination source
    [[ -f "$overlay_state" ]] || return 0
    while IFS=$'\t' read -r destination source; do
        [[ -n "$destination" && -n "$source" ]] || continue
        if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
            unlink "$destination"
        fi
    done <"$overlay_state"
}

merge_overlay_directory() {
    local source_dir="$1" destination_dir="$2" source destination name
    [[ -d "$source_dir" ]] || return 0
    mkdir -p "$destination_dir"
    shopt -s dotglob nullglob
    for source in "$source_dir"/*; do
        name="${source##*/}"
        destination="$destination_dir/$name"
        link_entry "$source" "$destination"
        if [[ -L "$destination" && "$(readlink "$destination")" == "$source" ]]; then
            printf '%s\t%s\n' "$destination" "$source" >>"$new_overlay_state"
        fi
    done
    shopt -u dotglob nullglob
}

prune_broken_native_links() {
    local native_dir="$1" entry target
    [[ -d "$native_dir" ]] || return 0
    shopt -s dotglob nullglob
    for entry in "$native_dir"/*; do
        [[ -L "$entry" && ! -e "$entry" ]] || continue
        target="$(readlink "$entry")"
        case "$target" in
            "$ai_dir"/*) unlink "$entry" ;;
        esac
    done
    shopt -u dotglob nullglob
}

# Revision 1 linked whole tool directories to the shared root. Turn only those
# exact legacy links back into real directories; their entries remain safely in
# the shared root and are linked back individually below.
prepare_native_collection() {
    local native_dir="$1" legacy_shared_dir="$2"
    if [[ -L "$native_dir" && "$(readlink "$native_dir")" == "$legacy_shared_dir" ]]; then
        unlink "$native_dir"
    fi
    if ! path_exists "$native_dir"; then
        mkdir -p "$native_dir"
    elif [[ ! -d "$native_dir" ]]; then
        printf 'WARN: cannot overlay into non-directory path: %s\n' "$native_dir" >&2
        conflict_count=$((conflict_count + 1))
    fi
}

write_overlay_config() {
    path_exists "$overlay_config" && return 0
    {
        printf '# Additional private AI overlay roots, one absolute or ~/ path per line.\n'
        printf '# Each root may contain skills/, agents/{claude,codex}/,\n'
        printf '# rules/{claude,codex}/, hooks/{claude,codex}/, workflows/,\n'
        printf '# agent-memory/, memory/, plans/, scripts/, and specs/.\n'
        printf '# Entries are linked individually; existing same-named entries win.\n'
        printf '# Example: ~/work/ai\n'
    } >"$overlay_config"
    chmod 600 "$overlay_config"
}

trim_space() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

load_overlay_roots() {
    local line root existing duplicate
    overlay_roots=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim_space "$line")"
        case "$line" in
            ""|\#*) continue ;;
        esac
        root="$line"
        case "$root" in
            "~") root="$HOME" ;;
            \~/*) root="$HOME/${root#\~/}" ;;
        esac
        case "$root" in
            /*) ;;
            *)
                printf 'WARN: ignoring non-absolute AI overlay root: %s\n' "$line" >&2
                conflict_count=$((conflict_count + 1))
                continue
                ;;
        esac
        if [[ ! -d "$root" ]]; then
            printf 'WARN: AI overlay root is unavailable; skipping: %s\n' "$root" >&2
            continue
        fi
        duplicate=false
        for existing in "${overlay_roots[@]}"; do
            [[ "$existing" == "$root" ]] && duplicate=true
        done
        [[ "$duplicate" == true ]] || overlay_roots+=("$root")
    done <"$overlay_config"
}

merge_additional_overlay() {
    local root="$1"
    merge_overlay_directory "$root/skills" "$ai_dir/skills"
    merge_overlay_directory "$root/agents/claude" "$ai_dir/agents/claude"
    merge_overlay_directory "$root/agents/codex" "$ai_dir/agents/codex"
    merge_overlay_directory "$root/rules/claude" "$ai_dir/rules/claude"
    merge_overlay_directory "$root/rules/codex" "$ai_dir/rules/codex"
    merge_overlay_directory "$root/hooks/claude" "$ai_dir/hooks/claude"
    merge_overlay_directory "$root/hooks/codex" "$ai_dir/hooks/codex"
    merge_overlay_directory "$root/workflows" "$ai_dir/workflows"
    merge_overlay_directory "$root/agent-memory" "$ai_dir/agent-memory"
    merge_overlay_directory "$root/memory" "$ai_dir/memory"
    merge_overlay_directory "$root/plans" "$ai_dir/plans"
    merge_overlay_directory "$root/scripts" "$ai_dir/scripts"
    merge_overlay_directory "$root/specs" "$ai_dir/specs"
}

render_shared_instructions() {
    local source="$ASSET_DIR/instructions/AGENTS.md.in"
    local destination="$ai_dir/AGENTS.md"
    local temporary content
    temporary="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-instructions.XXXXXX")"
    content="$(<"$source")"
    content="${content//@@AI_DIRECTORY@@/$ai_dir}"
    printf '%s\n' "$content" >"$temporary"
    if [[ -f "$destination" ]] && cmp -s "$temporary" "$destination"; then
        rm -f "$temporary"
        return 0
    fi
    path_exists "$destination" && backup_path "$destination"
    mv "$temporary" "$destination"
}

install_repo_assets() {
    local source name

    for source in "$ASSET_DIR/agents/claude"/*; do
        name="${source##*/}"
        link_entry "$source" "$ai_dir/agents/claude/$name"
    done
    for source in "$ASSET_DIR/agents/codex"/*; do
        name="${source##*/}"
        link_entry "$source" "$ai_dir/agents/codex/$name"
    done
    for source in "$ASSET_DIR/skills"/*; do
        name="${source##*/}"
        link_entry "$source" "$ai_dir/skills/$name"
    done

    link_entry "$SCRIPT_DIR/sync-ai-overlays.sh" "$ai_dir/scripts/sync-overlays"
    render_shared_instructions
    link_singleton "$ai_dir/AGENTS.md" "$HOME/.claude/CLAUDE.md"
    link_singleton "$ai_dir/AGENTS.md" "$HOME/.codex/AGENTS.md"
}

install_repo_hooks() {
    local source name
    if [[ "$INSTALL_AI_CLAUDE_HOOKS" == true ]]; then
        for source in "$ASSET_DIR/hooks/claude"/*; do
            name="${source##*/}"
            link_entry "$source" "$ai_dir/hooks/claude/$name"
        done
    fi
    if [[ "$INSTALL_AI_CODEX_HOOKS" == true ]]; then
        for source in "$ASSET_DIR/hooks/codex"/*; do
            name="${source##*/}"
            link_entry "$source" "$ai_dir/hooks/codex/$name"
        done
    fi
}

sync_canonical_overlay() {
    prepare_native_collection "$HOME/.claude/skills" "$ai_dir/skills"
    prepare_native_collection "$HOME/.codex/skills" "$ai_dir/skills"
    prepare_native_collection "$HOME/.claude/agent-memory" "$ai_dir/agent-memory"
    prepare_native_collection "$HOME/.claude/agents" "$ai_dir/agents/claude"
    prepare_native_collection "$HOME/.codex/agents" "$ai_dir/agents/codex"
    prepare_native_collection "$HOME/.claude/rules" "$ai_dir/rules/claude"
    prepare_native_collection "$HOME/.codex/rules" "$ai_dir/rules/codex"
    prepare_native_collection "$HOME/.claude/workflows" "$ai_dir/workflows"
    prepare_native_collection "$HOME/.claude/hooks" "$ai_dir/hooks/claude"
    prepare_native_collection "$HOME/.codex/hooks" "$ai_dir/hooks/codex"
    # plansDirectory points Claude directly at the shared directory. Remove only
    # our old whole-directory link so ~/.claude remains open for local additions.
    prepare_native_collection "$HOME/.claude/plans" "$ai_dir/plans"

    prune_broken_native_links "$HOME/.claude/skills"
    prune_broken_native_links "$HOME/.codex/skills"
    prune_broken_native_links "$HOME/.claude/agent-memory"
    prune_broken_native_links "$HOME/.claude/agents"
    prune_broken_native_links "$HOME/.codex/agents"
    prune_broken_native_links "$HOME/.claude/rules"
    prune_broken_native_links "$HOME/.codex/rules"
    prune_broken_native_links "$HOME/.claude/workflows"
    prune_broken_native_links "$HOME/.claude/hooks"
    prune_broken_native_links "$HOME/.codex/hooks"

    link_directory_entries "$ai_dir/skills" "$HOME/.claude/skills"
    link_directory_entries "$ai_dir/skills" "$HOME/.codex/skills"
    link_directory_entries "$ai_dir/agent-memory" "$HOME/.claude/agent-memory"
    link_directory_entries "$ai_dir/agents/claude" "$HOME/.claude/agents"
    link_directory_entries "$ai_dir/agents/codex" "$HOME/.codex/agents"
    link_directory_entries "$ai_dir/rules/claude" "$HOME/.claude/rules"
    link_directory_entries "$ai_dir/rules/codex" "$HOME/.codex/rules"
    link_directory_entries "$ai_dir/workflows" "$HOME/.claude/workflows"
    if [[ "$INSTALL_AI_CLAUDE_HOOKS" == true || "$AI_OVERLAY_SYNC_ONLY" == true ]]; then
        link_directory_entries "$ai_dir/hooks/claude" "$HOME/.claude/hooks"
    fi
    if [[ "$INSTALL_AI_CODEX_HOOKS" == true || "$AI_OVERLAY_SYNC_ONLY" == true ]]; then
        link_directory_entries "$ai_dir/hooks/codex" "$HOME/.codex/hooks"
    fi
}

mkdir -p \
    "$ai_dir/agent-memory" \
    "$ai_dir/agents/claude" \
    "$ai_dir/agents/codex" \
    "$ai_dir/hooks/claude" \
    "$ai_dir/hooks/codex" \
    "$ai_dir/memory" \
    "$ai_dir/plans" \
    "$ai_dir/rules/claude" \
    "$ai_dir/rules/codex" \
    "$ai_dir/scripts" \
    "$ai_dir/skills" \
    "$ai_dir/specs" \
    "$ai_dir/workflows"

write_overlay_config
load_overlay_roots
unlink_recorded_overlays
new_overlay_state="$(mktemp "${TMPDIR:-/tmp}/dotfiles-ai-overlays.XXXXXX")"

if [[ "$AI_OVERLAY_SYNC_ONLY" != true ]]; then
    [[ "$INSTALL_AI_SHARED_WORKSPACE" == true ]] && install_repo_assets
    install_repo_hooks
fi

for overlay_root in "${overlay_roots[@]}"; do
    merge_additional_overlay "$overlay_root"
done
mv "$new_overlay_state" "$overlay_state"
chmod 600 "$overlay_state"
sync_canonical_overlay

if (( backup_count > 0 )); then
    printf 'ai workspace: installed at %s; preserved %d replaced singleton path(s) in %s\n' \
        "$ai_dir" "$backup_count" "$backup_dir"
else
    rmdir "$backup_dir" 2>/dev/null || true
    printf 'ai workspace: installed at %s\n' "$ai_dir"
fi
if (( conflict_count > 0 )); then
    printf 'ai workspace: kept %d existing or invalid overlay entry/entries unchanged\n' \
        "$conflict_count"
fi
