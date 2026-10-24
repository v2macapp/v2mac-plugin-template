"""Package boundary checks, without Docker: python3 -m unittest discover -s Tests -p '*_test.py'."""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASE = "base@sha256:" + "a" * 64


class PackageTests(unittest.TestCase):
    def test_packages_and_refuses_invalid_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            plugin = work / "plugin"
            plugin.mkdir()
            manifest = json.loads((ROOT / "plugin.json").read_text())
            (plugin / "plugin.json").write_text(json.dumps(manifest))
            # Only stand in for the image build/export; exercise the real packager and hashing.
            # The saved image: the base's layer, then the plugin's own one.
            def saved(diff_ids):
                out = io.BytesIO()
                with tarfile.open(fileobj=out, mode="w") as t:
                    for name, data in [("manifest.json", json.dumps([{"Config": "config.json", "Layers": ["base.tar", "own.tar"]}]).encode()),
                                       ("config.json", json.dumps({"rootfs": {"diff_ids": diff_ids}}).encode()),
                                       ("base.tar", b"base layer"), ("own.tar", gzip.compress(b"own layer"))]:
                        info = tarfile.TarInfo(name)
                        info.size = len(data)
                        t.addfile(info, io.BytesIO(data))
                return out.getvalue()
            (work / "image.tar").write_bytes(saved(["sha256:base", "sha256:own"]))
            (work / "other.tar").write_bytes(saved(["sha256:other", "sha256:own"]))
            docker = work / "docker"
            docker.write_text('#!/bin/sh\ncase "$1 $4" in\n'
                              '*RootFS*) echo \'["sha256:base"]\';;\n'
                              'image*) echo "${IMAGE_ID:-sha256:' + "a" * 64 + '}";;\n'
                              'build*) exit "${BUILD_EXIT:-0}";;\n'
                              'save*) cat "${SAVED:-image.tar}";;\n'
                              '*) exit 99;;\nesac\n')
            docker.chmod(0o755)
            env = {**os.environ, "PATH": str(work) + os.pathsep + os.environ["PATH"]}

            def package(base=BASE, **extra):
                return subprocess.run([str(ROOT / "Scripts/package.sh"), str(plugin), base,
                                       "https://github.com/a/b/releases/download/v1/", "https://github.com/a/b", "b" * 40],
                                      cwd=work, env={**env, **extra}, capture_output=True, text=True)

            result = package()
            self.assertEqual(result.returncode, 0, result.stderr)
            built = json.loads((work / "dist/plugin.json").read_text())
            layer = built["layers"][0]
            archive = (work / "dist/my-plugin-0.1.0.tar.gz").read_bytes()
            self.assertEqual(built["from"], BASE)
            self.assertEqual(built["source"]["commit"], "b" * 40)
            self.assertEqual(layer["sha256"], hashlib.sha256(archive).hexdigest())
            self.assertEqual(layer["size"], len(archive))
            self.assertTrue(layer["url"].endswith("/my-plugin-0.1.0.tar.gz"))
            # Only the plugin's own layer ships, unzipped inside the gzipped archive.
            with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as t:
                self.assertEqual(t.getnames(), ["0.tar"])
                self.assertEqual(t.extractfile("0.tar").read(), b"own layer")
            self.assertNotEqual(package(SAVED="other.tar").returncode, 0)
            self.assertNotEqual(package("ghcr.io/a/base:latest").returncode, 0)
            self.assertNotEqual(package("ghcr.io/a/base@sha256:REPLACE").returncode, 0)
            self.assertNotEqual(package(IMAGE_ID="sha256:" + "b" * 64).returncode, 0)
            self.assertNotEqual(package(BUILD_EXIT="1").returncode, 0)
            manifest["id"] = "../../escape"
            (plugin / "plugin.json").write_text(json.dumps(manifest))
            self.assertNotEqual(package().returncode, 0)


if __name__ == "__main__":
    unittest.main()
