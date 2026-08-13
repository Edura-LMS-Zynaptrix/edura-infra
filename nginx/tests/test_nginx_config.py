import os
import re

NGINX_CONF_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "nginx.conf")
)

SERVICES = [
    ("auth_service", "8001", "/api/auth/"),
    ("user_service", "8002", "/api/users/"),
    ("course_service", "8003", "/api/courses/"),
    ("content_service", "8004", "/api/content/"),
    ("enrollment_service", "8005", "/api/enrollments/"),
    ("payment_service", "8006", "/api/payments/"),
    ("assessment_service", "8007", "/api/assessments/"),
    ("progress_service", "8008", "/api/progress/"),
    ("notification_service", "8009", "/api/notifications/"),
    ("analytics_service", "8010", "/api/analytics/"),
    ("admin_service", "8011", "/api/admin/"),
]


def read_nginx_conf():
    assert os.path.exists(NGINX_CONF_PATH), f"nginx.conf not found at {NGINX_CONF_PATH}"
    with open(NGINX_CONF_PATH, "r", encoding="utf-8") as f:
        return f.read()


def test_nginx_conf_exists():
    content = read_nginx_conf()
    assert len(content) > 0


def test_all_11_upstream_blocks_exist():
    content = read_nginx_conf()
    for service_name, port, _ in SERVICES:
        pattern = (
            rf"upstream\s+{service_name}\s*\{{[^}}]*server\s+{service_name}:{port};"
        )
        assert re.search(
            pattern, content
        ), f"Upstream block for {service_name}:{port} not found in nginx.conf"


def test_all_11_location_routes_exist():
    content = read_nginx_conf()
    for service_name, _, path in SERVICES:
        pattern = rf"location\s+{re.escape(path)}\s*\{{[\s\S]*?proxy_pass\s+http://{service_name}/;"
        assert re.search(
            pattern, content
        ), f"Location route for {path} -> http://{service_name}/ not found in nginx.conf"


def test_rate_limiting_configured():
    content = read_nginx_conf()
    assert (
        "limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;" in content
    ), "Rate limit zone=api:10m rate=100r/m missing"
    assert "limit_req_status 429;" in content, "limit_req_status 429 missing"
    assert (
        "limit_req zone=api burst=20 nodelay;" in content
    ), "limit_req zone=api missing in server block"


def test_cors_headers_configured():
    content = read_nginx_conf()
    assert "Access-Control-Allow-Origin" in content, "CORS Allow-Origin header missing"
    assert (
        "http://localhost:3000" in content
    ), "CORS Allow-Origin http://localhost:3000 missing"
    assert (
        "Access-Control-Allow-Methods" in content
    ), "CORS Allow-Methods header missing"
    assert "$request_method = 'OPTIONS'" in content, "OPTIONS preflight block missing"


def test_proxy_headers_forwarded():
    content = read_nginx_conf()
    assert "proxy_set_header Host $host;" in content, "Proxy Host header missing"
    assert (
        "proxy_set_header X-Real-IP $remote_addr;" in content
    ), "Proxy X-Real-IP header missing"
    assert (
        "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;" in content
    ), "Proxy X-Forwarded-For header missing"
    assert (
        "proxy_set_header X-Forwarded-Proto $scheme;" in content
    ), "Proxy X-Forwarded-Proto header missing"
