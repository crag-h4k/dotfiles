#!/usr/bin/env bash
# scripts/install-openviking.sh
# Stage a wheel-based Python environment before activating its stable pointer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[[ "${INSTALL_AI_OPENVIKING:-false}" == true ]] || exit 0
OPENVIKING_VERSION="${OPENVIKING_VERSION:-0.4.23}"
OPENVIKING_INSTALL_ROOT=$(openviking_install_root)
[[ "$OPENVIKING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "OpenViking requires an exact release version"
command -v uv >/dev/null 2>&1 || die "OpenViking requires uv; install the approved package first"
command -v python3 >/dev/null 2>&1 || die "OpenViking requires Python 3.10+"

healthy() {
    local python="$1"
    [[ -x "$python" ]] || return 1
    "$python" - "$OPENVIKING_VERSION" <<'PY'
import importlib.metadata
import json
import os
import sys
import tempfile
from pathlib import Path

# Import checks must not load a user's private model configuration.
temporary = tempfile.TemporaryDirectory()
config = Path(temporary.name) / "ov.conf"
config.write_text(json.dumps({"storage": {"workspace": str(Path(temporary.name) / "data")}}))
os.environ["OPENVIKING_CONFIG_FILE"] = str(config)
import openviking
import openviking_sdk
import litellm
from litellm.llms.github_copilot.authenticator import Authenticator
from openviking.storage.vectordb.engine import ENGINE_VARIANT
import openviking.pyagfs

assert importlib.metadata.version("openviking") == sys.argv[1]
assert ENGINE_VARIANT != "unavailable"
PY
}

mkdir -p "$OPENVIKING_INSTALL_ROOT/releases"
if healthy "$OPENVIKING_INSTALL_ROOT/current/bin/python" 2>/dev/null; then
    info "OpenViking $OPENVIKING_VERSION is current"
else
    stage=$(mktemp -d "$OPENVIKING_INSTALL_ROOT/releases/$OPENVIKING_VERSION.XXXXXX")
    info "OpenViking $OPENVIKING_VERSION: creating an isolated Python environment"
    uv venv --python "${OPENVIKING_PYTHON:-python3}" "$stage"
    info "OpenViking $OPENVIKING_VERSION: installing prebuilt packages"
    uv pip install --python "$stage/bin/python" --only-binary :all: "openviking==$OPENVIKING_VERSION"
    healthy "$stage/bin/python" || die "OpenViking import verification failed; previous runtime remains active"
    "$stage/bin/openviking-server" --help >/dev/null
    python3 - "$stage" "$OPENVIKING_INSTALL_ROOT/current" <<'PY'
import os
import sys
import uuid
from pathlib import Path

stage, current = map(Path, sys.argv[1:])
if current.exists() and not current.is_symlink():
    raise SystemExit("Refusing to replace a non-symlink OpenViking runtime")
temporary = current.with_name(".current-" + uuid.uuid4().hex)
temporary.symlink_to(stage.resolve(), target_is_directory=True)
os.replace(temporary, current)
PY
fi

# This installer-owned location record is private runtime metadata, not ov.conf.
python3 - "$OPENVIKING_INSTALL_ROOT" <<'PY'
import json
import os
import tempfile
from pathlib import Path
import sys

root = Path.home() / ".openviking"
root.mkdir(mode=0o700, parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=".runtime-", dir=root)
with os.fdopen(fd, "w") as handle:
    json.dump({"install_root": str(Path(sys.argv[1]).resolve())}, handle)
    handle.write("\n")
os.replace(temporary, root / "runtime.json")
PY
info "OpenViking is installed. Private configuration and service activation remain explicit."
