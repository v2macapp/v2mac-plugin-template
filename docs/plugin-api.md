# V2Mac Sandbox plugin API, version 1

A plugin is one app that runs in a V2Mac mini VM and shows on the Mac as its own app
(`<Name> — <Mini VM>.app`). Every mini VM has its own exit server and can't reach the Mac, other
mini VMs or the network except through that exit.

## plugin.json

| Field | Required | Meaning |
|---|---|---|
| `api` | yes | `1`. Additive only: a V2Mac that knows an older api hides the plugin. |
| `id` | yes | Letters, digits, `.` and `-`, at most 64. Stays the same across versions. |
| `name`, `version` | yes | Shown to the user. `name` at most 64 characters. |
| `display` | yes | `pty`: opens in the user's Terminal. `gui`: its own window. |
| `launch.cmd` | yes | The command, as a list (no shell unless you run one). |
| `launch.env` | no | Extra environment, `NAME: value` (no newlines). |
| `permissions` | no | Any of `clipboard`, `shared`, `ssh-agent`, `sound`, `microphone`; the user approves them at install, and V2Mac asks again when an open app first uses `sound`, `microphone` or `ssh-agent`. |
| `publisher`, `changelog`, `securityNotes` | no | Publisher, release notes and permission rationale for store review. |
| `description` | no | One or two sentences on what the app does, shown in the V2Mac Store window. |
| `icon` | no | SVG filename in the plugin folder, uploaded as a release asset. At most 64 KB, plain shapes and gradients only (`path`, `rect`, `circle`, `g`…, at most 1000 elements): no `use`, text, images, `style`, scripts, DOCTYPE or references other than `url(#id)`. The store copies it into its signed index; V2Mac shows it in the store and frames it in the mini VM's colour as the Mac app's icon. Without one, the app gets its initial. |
| `settings` | no | Reserved; ignored by api 1. |
| `from`, `source`, `layers` | filled in | Written by `Scripts/package.sh` at release; don't edit them. |

## What the runtime gives your app

- A home (`/root`) on the mini VM's disk, or in memory when the mini VM is Disposable.
- `/run/v2mac/exit.json`: `ip`, `country`, `city`, `latitude`, `longitude`, `timezone` of the
  mini VM's exit. Read-only; replaced atomically when the exit changes (watch the folder with inotify).
- `TZ`: the exit's time zone at launch.
- `~/Shared` (currently `gui` only, with `shared`): `~/V2Mac Sandbox/<Mini VM>/Shared` on the Mac. What you write
  there is marked as downloaded (quarantine).
- Clipboard (only with `clipboard`, `gui`): the Mac's text reaches you on ⌘V; your copies reach the
  Mac. The user can switch either direction off per mini VM.
- `SSH_AUTH_SOCK` (only with `ssh-agent`, `pty`): the Mac's ssh-agent while your app is open, once
  the user allows it at the first connection.
- Sound (`gui`): your own sound card with speakers (`sound`) and a microphone (`microphone`), through
  PipeWire (ALSA or PulseAudio). When your app first plays or records, V2Mac asks the user; until they
  allow it, what you play is silent and what you record is silence. The Mac's microphone is open only
  while you record. Without either permission there is no sound card.
- `gui` apps run under sway (fullscreen, no decorations) at the window's size; `pty` apps get a real
  terminal with resize and signals.

Nothing else: no vsock, no firewall or route changes, no other mini VMs, no Mac paths. Your
container runs rootless with no capabilities, a read-only root and a seccomp profile.

## Building

`Containerfile` must start `ARG BASE` / `FROM ${BASE}`; `base.txt` names the released base: the
sandbox's own root (Debian 13 with sway, wayvnc, PipeWire, GTK, fonts and the terminal tools), the same
for `pty` and `gui` apps. Every sandbox already has it, so users download only what your app adds.
Install packages from Debian's archive only, and remove apt's lists and caches in the same `RUN`
(`rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin`), or they ship with your app.
`Scripts/package.sh . "$(cat base.txt)" <url prefix>` builds the image, keeps only the layers your
`Containerfile` adds, gzips them into one archive and writes `dist/plugin.json`; the release workflow
does this at a tag.
For archive and Docker names, the packager accepts 1–64 ASCII letters, digits, dots or hyphens in
`id` and `version`, starting with a letter or digit. Run
`python3 -m unittest discover -s Tests -p '*_test.py'` for its boundary checks.

`layers` lists exactly one archive: a gzipped tar of the app's own layer tars (`0.tar`, `1.tar`, …),
which the sandbox unpacks once and stacks on its root. Deleting a whole directory and recreating it in
a later layer (an opaque directory) is refused; do such work in one `RUN`. The signed index pins the
archive's exact bytes. Submission CI checks `from` against the store's `bases.json`;
the helper checks it against the base list bundled with its own release. Review the Containerfile
at the pinned source commit too: a manifest's `from` declaration alone does not prove ancestry.

## Local testing

For platform development before the base is released, run `Scripts/build-base.sh` in the sandbox
repo (after `build-rootfs.sh`). Its `out/images/bases.json` lists a local reference such as
`base@sha256:<image id>`. From this repo, package a sample with:

```sh
Scripts/package.sh hello-gui 'base@sha256:<image id>' \
  http://127.0.0.1:8765 https://github.com/your-name/your-plugin <commit>
```

Use the resulting manifest and archive in a local index signed with a throwaway Ed25519 test key.
Build the helper after the base images so it bundles that base list. Serve the index, signature and
archive on loopback, then launch **V2MacDev** with `V2MAC_SANDBOX_STORE=http://127.0.0.1:8765/`
and `V2MAC_SANDBOX_STORE_KEY=<base64 public key>`. Add the plugin through that store. Never use the
production store's signing key for a test. A clean-Mac install remains a release check.

From Folder only reads `plugin.json` and runs on the guest rootfs; it does not build the Containerfile
or copy files into the image. Use it only for commands already present there. The template's
`start.sh` needs the packaged image.
