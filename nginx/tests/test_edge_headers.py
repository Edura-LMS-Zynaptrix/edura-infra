import os

import yaml

EDGE_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "k8s", "base", "50-edge.yaml")
)

REQUIRED_HEADERS = (
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
)


def read_caddyfile():
    with open(EDGE_PATH, "r", encoding="utf-8") as f:
        documents = [d for d in yaml.safe_load_all(f) if d]
    return documents[0]["data"]["Caddyfile"]


def test_edge_sets_security_response_headers():
    caddyfile = read_caddyfile()
    for header in REQUIRED_HEADERS:
        assert header in caddyfile, f"{header} missing from the Caddy edge config"


def test_edge_hides_server_banner_and_still_proxies_to_gateway():
    caddyfile = read_caddyfile()
    assert "-Server" in caddyfile
    assert "reverse_proxy gateway:80" in caddyfile
