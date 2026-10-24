# V2Mac Sandbox plugin template

Make an app for V2Mac's Secure Sandbox: it runs in a mini VM with its own exit server and shows on
the Mac as its own app. API: [docs/plugin-api.md](docs/plugin-api.md).

1. Use this template. Set `id`, `name` and `launch` in `plugin.json`; add what your app needs to
   `Containerfile`; keep `start.sh` or replace it.
2. Put the released base image in `base.txt` (from the V2Mac store's `bases.json`).
3. Build it: `Scripts/package.sh . "$(cat base.txt)" <release URL prefix> <repo URL> <commit>`.
   Test the resulting `dist/plugin.json` and archive through a local test store in a V2Mac dev build
   (see [local testing](docs/plugin-api.md#local-testing)).
4. Release: push a tag. The workflow attaches the image and the filled `plugin.json`.
5. Submit: a pull request to the V2Mac store adding `submissions/<id>.json`
   (`{"repo": "https://github.com/<you>/<repo>", "tag": "<tag>"}`). Its CI checks the release.

Samples: `hello-pty` (terminal, ssh-agent) and `hello-gui` (window, clipboard, Shared).
To release a sample as its own plugin, copy its `Containerfile`, `plugin.json`, `icon.svg` and `base.txt`
over the root files in a copy of this template. The release workflow packages the root plugin.
In this repo, `hello-pty-v*` and `hello-gui-v*` tags release the corresponding sample; `v*` tags
release the root plugin. The base files pin the base of a sandbox release (`ghcr.io/lordversa/v2mac-base@sha256:…`, the
sandbox's own root); never substitute an unpinned tag. Maintainers: publish the GHCR base package with
public read access and copy the sandbox release's `bases.json` into the store before accepting
submissions built on it.
Licence: 0BSD.
