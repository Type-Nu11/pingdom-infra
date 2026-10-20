"""Check the configured normalized-path policy; nginx runtime tested separately."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "configs/conf.d/http/swagger_access.conf").read_text()
PATTERN = re.compile(re.search(r"~\*(\S+) 1;", CONFIG)[1], re.I)


class SwaggerAccessTest(unittest.TestCase):
    def test_protected_routes(self):
        for path in ["/swagger-ui", "/swagger-ui/", "/swagger-ui.html",
                     "/swagger-ui/index.html", "/SWAGGER-UI/index.html",
                     "/v3/api-docs", "/v3/api-docs/app",
                     "/v3/api-docs/swagger-config", "/v3/api-docs.yaml",
                     "/v2/api-docs", "/swagger-resources/configuration/ui",
                     "/webjars/swagger-ui/index.html",
                     "/webjars/springfox-swagger-ui/swagger-ui.css",
                     "/api/v3/api-docs/app"]:
            with self.subTest(path=path):
                self.assertIsNotNone(PATTERN.match(path))

    def test_normal_apis_unchanged(self):
        for path in ["/", "/auth/login", "/users/me", "/offers", "/console/login"]:
            self.assertIsNone(PATTERN.match(path))

    def test_both_servers_guarded(self):
        template = (ROOT / "nginx.conf.template").read_text()
        self.assertEqual(template.count("if ($swagger_denied) { return 403; }"), 2)
        self.assertIn("34.127.98.202/32 1;", CONFIG)
        self.assertNotIn("$http_x_forwarded_for", CONFIG)


if __name__ == "__main__":
    unittest.main()
