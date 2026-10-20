import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SwaggerPublicTest(unittest.TestCase):
    def test_no_source_ip_gate(self):
        template = (ROOT / "nginx.conf.template").read_text()
        self.assertNotIn("swagger_denied", template)
        self.assertNotIn("swagger_access.conf", template)
        self.assertFalse((ROOT / "configs/conf.d/http/swagger_access.conf").exists())
        routes = (ROOT / "configs/conf.d/web/locations.conf").read_text()
        self.assertIn("location ^~ /swagger-ui/", routes)
        self.assertIn("location ^~ /v3/api-docs/", routes)


if __name__ == "__main__":
    unittest.main()
