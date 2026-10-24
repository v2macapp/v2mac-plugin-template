# CLAUDE.md (plugin-template)

GitHub template repo (0BSD) for Secure Sandbox plugins, plus the samples `hello-gui` and
`hello-pty` that test the platform. Plan: `../sandbox/docs/PLAN.md` §6–7, milestone M6
(samples in M3/M4).

- A plugin = `Containerfile` `FROM` the released base digest, the sandbox's own root (store CI
  rejects anything else), `plugin.json` (plugin API, integer `api`, additive only), an icon, and a CI
  workflow that packages only the layers it adds at a tag and attaches them to a GitHub Release.
- Plugins get only what `plugin.json` asks for and the user approved. Never add vsock, host paths or
  network setup to a plugin; the runtime owns those. `settings` is reserved, not used by api 1.
- Keep it minimal: it is what every plugin author copies.
- Public GitHub template: `LordVersA/v2mac-plugin-template`. Push when the user asks or CI needs to see it.
