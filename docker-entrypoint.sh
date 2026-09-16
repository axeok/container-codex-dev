#!/bin/sh
set -eu

: "${MODEL_PROVIDER_ROUTE:?MODEL_PROVIDER_ROUTE is required}"
: "${MODEL_PROVIDER_API_TOKEN?MODEL_PROVIDER_API_TOKEN must be set, but may be empty}"

mkdir -p /root/.codex /root/.ssh /workspace
chmod 700 /root/.ssh

python3 - <<'PY'
import json
import os
import re
from pathlib import Path

config_path = Path("/root/.codex/config.toml")
selection_start = "# BEGIN container-codex-dev provider selection"
selection_end = "# END container-codex-dev provider selection"
selection_block = "\n".join(
    [
        selection_start,
        'model_provider = "custom"',
        selection_end,
        "",
    ]
)
provider_start = "# BEGIN container-codex-dev custom provider"
provider_end = "# END container-codex-dev custom provider"
provider_block = "\n".join(
    [
        provider_start,
        "[model_providers.custom]",
        'name = "Custom"',
        f"base_url = {json.dumps(os.environ['MODEL_PROVIDER_ROUTE'])}",
        'wire_api = "responses"',
        f"experimental_bearer_token = {json.dumps(os.environ['MODEL_PROVIDER_API_TOKEN'])}",
        provider_end,
        "",
    ]
)

existing = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
selection_pattern = re.compile(
    rf"(?ms)^{re.escape(selection_start)}$.*?^{re.escape(selection_end)}$\n?"
)
provider_pattern = re.compile(
    rf"(?ms)^{re.escape(provider_start)}$.*?^{re.escape(provider_end)}$\n?"
)

if selection_pattern.search(existing):
    updated = selection_pattern.sub(lambda _: selection_block, existing, count=1)
else:
    if re.search(r"(?m)^\s*model_provider\s*=", existing):
        raise SystemExit(
            f"Refusing to overwrite an unmanaged model_provider in {config_path}"
        )
    updated = selection_block + existing

if provider_pattern.search(updated):
    updated = provider_pattern.sub(lambda _: provider_block, updated, count=1)
else:
    if re.search(r"(?m)^\s*\[model_providers\.custom\]\s*$", updated):
        raise SystemExit(
            f"Refusing to overwrite an unmanaged custom provider in {config_path}"
        )
    separator = "" if not updated or updated.endswith("\n") else "\n"
    updated = updated + separator + provider_block

config_path.write_text(updated, encoding="utf-8")
config_path.chmod(0o600)
PY

if [ ! -s /root/.ssh/gateway_key ]; then
    rm -f /root/.ssh/gateway_key /root/.ssh/gateway_key.pub
    ssh-keygen -q -t ed25519 -N '' -C 'codex-gateway' -f /root/.ssh/gateway_key
elif [ ! -s /root/.ssh/gateway_key.pub ]; then
    ssh-keygen -y -f /root/.ssh/gateway_key > /root/.ssh/gateway_key.pub
fi

{
    cat /root/.ssh/gateway_key.pub
    if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
        printf '%s\n' "$SSH_AUTHORIZED_KEY"
    fi
} > /root/.ssh/authorized_keys

chmod 600 /root/.ssh/gateway_key /root/.ssh/authorized_keys
chmod 644 /root/.ssh/gateway_key.pub

exec "$@"
