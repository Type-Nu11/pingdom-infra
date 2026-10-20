import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class RealIPConfigTest(unittest.TestCase):
    def test_gateway_trust_matches_compose(self):
        config = (ROOT / "configs/conf.d/http/real_ip.conf").read_text()
        compose = (ROOT / "docker-compose.yml").read_text()
        trusted = re.findall(r"^set_real_ip_from\s+([^;]+);", config, re.M)
        self.assertEqual(trusted, ["172.30.79.1"])
        self.assertIn("gateway: " + trusted[0], compose)
        self.assertIn("real_ip_header X-Real-IP;", config)
        self.assertIn("real_ip_recursive off;", config)
        self.assertIn('"127.0.0.1:8081:8081"', compose)
        self.assertIn('"127.0.0.1:8082:8082"', compose)
        self.assertNotIn('"8081:8081"', compose)
        self.assertNotIn('"8082:8082"', compose)
        self.assertIn("include configs/conf.d/http/real_ip.conf;",
                      (ROOT / "nginx.conf.template").read_text())


if __name__ == "__main__":
    unittest.main()
