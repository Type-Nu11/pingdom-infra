"""Exercise real Nginx routing; stub only the Lua authentication boundary.

Run: python3 tests/web_routing_test.py (requires nginx with auth_request).
No Docker, backend, console, Redis, or production JWT library is used.
"""
import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Backend(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/__auth':
            self.send_response(204 if self.headers.get('Authorization') == 'Bearer fixture' else 401)
            self.end_headers()
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.path.encode())

    def log_message(self, *args):
        pass


class WebRoutingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        nginx = os.environ.get('NGINX_BIN') or shutil.which('nginx')
        if not nginx:
            raise RuntimeError('Install nginx with auth_request or set NGINX_BIN')
        cls.resources = contextlib.ExitStack()
        cls.addClassCleanup(cls.resources.close)
        temp = Path(cls.resources.enter_context(tempfile.TemporaryDirectory(prefix='web-routing-')))
        (temp / 'logs').mkdir()
        backend = ThreadingHTTPServer(('127.0.0.1', 0), Backend)
        cls.resources.callback(backend.server_close)
        thread = threading.Thread(target=backend.serve_forever, daemon=True)
        thread.start()
        cls.resources.callback(backend.shutdown)
        # Bind a free local port; Nginx will bind it once the socket is released.
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        cls.base = f'http://127.0.0.1:{port}'
        cls.client = urllib.request.build_opener(NoRedirect())

        configs = temp / 'configs'
        shutil.copytree(ROOT / 'configs', configs)
        substitutions = {
            '${BACKEND_HOST}': '127.0.0.1', '${BACKEND_PORT}': str(backend.server_port),
            '${CONSOLE_HOST}': '127.0.0.1', '${CONSOLE_PORT}': str(backend.server_port),
            '${MCP_HOST}': '127.0.0.1', '${MCP_PORT}': str(backend.server_port),
        }
        for path in configs.rglob('*.conf'):
            text = path.read_text()
            for key, value in substitutions.items():
                text = text.replace(key, value)
            # Keep production locations, proxy settings and include structure.
            # Native Nginx cannot execute OpenResty's Lua JWT access handler.
            text = text.replace('access_by_lua_file /src/lua/web_entry.lua;',
                                'auth_request /__routing_test_auth;')
            path.write_text(text)
        (temp / 'nginx.conf').write_text(f'''
worker_processes 1;
pid logs/nginx.pid;
error_log logs/error.log;
events {{ worker_connections 128; }}
http {{
    access_log off;
    include configs/conf.d/http/ratelimit.conf;
    map $http_accept_encoding $pingcha_accept_encoding {{ default $http_accept_encoding; }}
    map $http_if_none_match $pingcha_if_none_match {{ default $http_if_none_match; }}
    map $http_if_modified_since $pingcha_if_modified_since {{ default $http_if_modified_since; }}
    server {{
        listen 127.0.0.1:{port};
        absolute_redirect off;
        location = /__routing_test_auth {{
            internal;
            proxy_pass http://127.0.0.1:{backend.server_port}/__auth;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
        }}
        include configs/conf.d/web/locations.conf;
    }}
}}
''')
        command = [nginx, '-p', str(temp) + '/', '-c', str(temp / 'nginx.conf')]
        subprocess.run(command + ['-t'], check=True, capture_output=True, timeout=10)
        process = subprocess.Popen(command + ['-g', 'daemon off;'], stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)

        def stop():
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)

        cls.resources.callback(stop)
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError((temp / 'logs/error.log').read_text())
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            raise RuntimeError('Test Nginx did not become ready')

    def request(self, path, authenticated=False):
        time.sleep(0.04)  # Stay below the production web rate limit (30 r/s).
        headers = {'Authorization': 'Bearer fixture'} if authenticated else {}
        req = urllib.request.Request(self.base + path, headers=headers)
        try:
            response = self.client.open(req, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, response.headers, response.read().decode()

    def test_unknown_paths_redirect_with_and_without_token(self):
        for path in ('/unknown', '/unknown/deep?next=https://example.test',
                     '/users-typo', '/places-typo', '/mcp-typo', '/UNKNOWN'):
            for authenticated in (False, True):
                with self.subTest(path=path, authenticated=authenticated):
                    status, headers, _ = self.request(path, authenticated)
                    self.assertEqual(status, 302)
                    self.assertEqual(headers['Location'], '/console/login')

    def test_api_namespaces_still_require_authentication(self):
        for path in ('/users/me', '/places', '/admin/places', '/community/posts',
                     '/merchant-owner/me', '/analysis/reports', '/voice-ai/sessions',
                     '/consultations', '/coupons', '/events', '/firebase/tokens',
                     '/location-check-ins', '/notifications', '/offers', '/payments',
                     '/popup-campaigns', '/reservations', '/routes', '/scout-field-reports',
                     '/visit-verification-sessions', '/visitor-verification-reports',
                     '/mcp', '/oauth2/authorization/google'):
            with self.subTest(path=path):
                status, headers, _ = self.request(path)
                self.assertEqual(status, 401)
                self.assertNotIn('Location', headers)

    def test_authenticated_api_keeps_path_and_query(self):
        for path in ('/places?page=1', '/users/me', '/community/posts?size=10',
                     '/users/not-a-real-endpoint', '/mcp'):
            with self.subTest(path=path):
                status, headers, body = self.request(path, authenticated=True)
                self.assertEqual(status, 200)
                self.assertEqual(body, path)
                self.assertNotIn('Location', headers)

    def test_public_routes_and_login_do_not_loop(self):
        for path, upstream in (('/console/login', '/login'),
                               ('/console/fixture.css', '/fixture.css'),
                               ('/api/auth/login', '/api/auth/login'),
                               ('/auth/login', '/auth/login'),
                               ('/actuator/health', '/actuator/health'),
                               ('/swagger-ui/index.html', '/swagger-ui/index.html'),
                               ('/v3/api-docs/app', '/v3/api-docs/app')):
            with self.subTest(path=path):
                status, headers, body = self.request(path)
                self.assertEqual(status, 200)
                self.assertEqual(body, upstream)
                self.assertNotIn('Location', headers)
        for path in ('/', '/console', '/operator'):
            with self.subTest(path=path):
                status, headers, _ = self.request(path)
                self.assertEqual(status, 302)
                self.assertEqual(headers['Location'], '/console/login')


if __name__ == '__main__':
    unittest.main()
