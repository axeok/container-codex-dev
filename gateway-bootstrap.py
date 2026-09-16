import json
import os
import time
import urllib.error
import urllib.request


gateway_url = os.environ.get("CODEX_GATEWAY_URL", "http://codex-gateway:3000").rstrip("/")
username = os.environ.get("CODEX_GATEWAY_ADMIN_USERNAME", "admin")
password = os.environ["CODEX_GATEWAY_ADMIN_PASSWORD"]


def request(path, *, token=None, payload=None):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{gateway_url}{path}", data=body, headers=headers, method="POST" if body else "GET"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gateway returned HTTP {error.code} for {path}: {details}") from error


def login():
    last_error = None
    for _ in range(12):
        try:
            return request(
                "/api/auth/login",
                payload={"username": username, "password": password},
            )["token"]
        except (OSError, RuntimeError, KeyError) as error:
            last_error = error
            time.sleep(2)
    raise RuntimeError("Could not log in to Codex Gateway") from last_error


token = login()
hosts = request("/api/hosts", token=token)
host = next(
    (
        item
        for item in hosts
        if item.get("sshHost") == "codex" and item.get("username") == "root"
    ),
    None,
)

if host is None:
    host = request(
        "/api/hosts",
        token=token,
        payload={
            "name": "Codex",
            "sshHost": "codex",
            "username": "root",
            "port": 22,
            "authMode": "privateKey",
            "privateKeyPath": "/ssh/gateway_key",
            "privateKey": None,
            "password": None,
            "proxyUrl": None,
        },
    )

host_id = int(host["id"])
projects = request(f"/api/projects?hostId={host_id}", token=token)
if not any(item.get("remotePath") == "/workspace" for item in projects):
    request(
        "/api/projects",
        token=token,
        payload={"hostId": host_id, "name": "Workspace", "remotePath": "/workspace"},
    )

print("Codex Gateway host and workspace are ready")
