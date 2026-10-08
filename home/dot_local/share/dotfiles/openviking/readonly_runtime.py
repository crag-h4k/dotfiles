# home/dot_local/share/dotfiles/openviking/readonly_runtime.py
"""Prepare the selected Copilot model before using the upstream runtime."""
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, new_url):
        return None


def prepare_models(config):
    models = [config.get("vlm", {}).get("model", ""),
              config.get("embedding", {}).get("dense", {}).get("model", "")]
    selected = [model.removeprefix("github_copilot/") for model in models
                if model.startswith("github_copilot/")]
    if not selected:
        return
    import litellm
    from litellm.llms.github_copilot.authenticator import Authenticator
    from litellm.llms.github_copilot.common_utils import (
        DEFAULT_GITHUB_COPILOT_API_BASE,
        get_copilot_default_headers,
    )

    auth = Authenticator()
    token_file = Path(auth.access_token_file)
    if not token_file.is_file() or not token_file.read_text().strip():
        raise ValueError("Copilot login missing; run openvikingctl auth-copilot in your terminal")
    key = auth.get_api_key()
    base = auth.get_api_base() or DEFAULT_GITHUB_COPILOT_API_BASE
    parsed = urllib.parse.urlparse(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Copilot model inventory requires an authenticated HTTPS endpoint")
    request = urllib.request.Request(base.rstrip("/") + "/models",
                                    headers=get_copilot_default_headers(key))
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
        payload = json.load(response)
    inventory = {model["id"]: model for model in payload.get("data", payload.get("models", []))}
    for model_id in selected:
        model = inventory.get(model_id)
        if model is None or (model.get("policy") or {}).get("state") == "disabled":
            raise ValueError("Selected Copilot model is unavailable on this account: " + model_id)
        capabilities = model.get("capabilities", {})
        limits = capabilities.get("limits", {})
        supports = capabilities.get("supports", {})
        endpoints = model.get("supported_endpoints") or []
        if capabilities.get("type") == "embeddings":
            mode = "embedding"
        elif "/responses" in endpoints and "/chat/completions" not in endpoints:
            mode = "responses"
        else:
            mode = "chat"
        metadata = {
            "litellm_provider": "github_copilot", "mode": mode,
            "supports_function_calling": bool(supports.get("tool_calls")),
            "supports_parallel_function_calling": bool(supports.get("parallel_tool_calls")),
            "supports_response_schema": bool(supports.get("structured_outputs")),
            "supports_reasoning": bool(supports.get("reasoning_effort")),
        }
        for source, target in (("max_prompt_tokens", "max_input_tokens"),
                               ("max_output_tokens", "max_output_tokens")):
            if limits.get(source):
                metadata[target] = limits[source]
        litellm.register_model({"github_copilot/" + model_id: metadata})


def main():
    action, path = sys.argv[1:3]
    config_path = Path(path)
    os.environ["OPENVIKING_CONFIG_FILE"] = str(config_path)
    config = json.loads(os.path.expandvars(config_path.read_text()))
    prepare_models(config)
    if action == "run":
        from openviking_cli.server_bootstrap import main as server_main
        sys.argv = ["openviking-server", "--config", str(config_path), "--host", "127.0.0.1",
                    "--port", str(config["server"].get("port", 1933))]
        server_main()
    elif action == "probe":
        from openviking_cli.utils.config.open_viking_config import OpenVikingConfig
        settings = OpenVikingConfig.from_dict(config)
        settings.vlm.max_tokens = 256
        embedder = settings.embedding.get_embedder()
        start = time.perf_counter()
        vector = embedder.embed("OpenViking synthetic embedding probe", is_query=True).dense_vector
        embedding_ms = (time.perf_counter() - start) * 1000
        if len(vector) != settings.embedding.dense.dimension:
            raise ValueError("configured embedding dimension does not match the selected model")
        start = time.perf_counter()
        reply = settings.vlm.get_completion(prompt="Reply with exactly OK.")
        if not isinstance(reply, str) or not reply.strip():
            raise ValueError("extraction model returned an empty response")
        print(json.dumps({"embedding_ms": round(embedding_ms, 2), "dimension": len(vector),
                          "vlm_ms": round((time.perf_counter() - start) * 1000, 2),
                          "model_response_received": True}))
    else:
        raise ValueError("unknown runtime action")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        raise SystemExit("OpenViking model metadata HTTP " + str(error.code))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
