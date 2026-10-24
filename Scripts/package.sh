#!/bin/sh
# package.sh <plugin dir> <base> <url prefix> [repo] [commit]: builds the plugin's image FROM <base>
# (a released base, exactly as the store's bases.json lists it: the sandbox's own root, which every
# sandbox already has), keeps only the layers the plugin adds, gzips them into one archive and writes
# dist/plugin.json with that archive's URL, SHA-256 and size filled in. The release workflow runs
# this at a tag; locally, point <url prefix> at a test store (http://127.0.0.1:<port>/...).
# PROXY= sets a download proxy for the build.
set -e
[ "$#" -ge 3 ] && [ "$#" -le 5 ] || { echo "usage: package.sh <plugin dir> <base> <url prefix> [repo] [commit]" >&2; exit 2; }
dir=$1 base=$2 prefix=$3 repo=${4:-local} commit=${5:-local}
[ -f "$dir/plugin.json" ] && [ -n "$prefix" ] || { echo "usage: package.sh <plugin dir> <base> <url prefix> [repo] [commit]"; exit 2; }
id=$(python3 - "$dir/plugin.json" "$base" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
for field in ("id", "version"):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,63}", m[field]):
        sys.exit(f"{field} must be 1–64 letters, digits, dots or hyphens, starting with a letter or digit")
if not re.fullmatch(r"(?:base|[a-z0-9./:_-]+/[a-z0-9._-]+)@sha256:[0-9a-f]{64}", sys.argv[2]):
    sys.exit("base must be a released image pinned by SHA-256; replace the placeholder in base.txt")
print(m["id"] + "-" + m["version"])
PY
)
mkdir -p dist
# A registry digest is the FROM as is; a local base (`base@sha256:<image id>`, sandbox's
# Scripts/build-base.sh) is its v2mac/ tag, checked to be that very image.
case "$base" in
*/*) from=$base ;;
*) from=v2mac/${base%@*}
   [ "$(docker image inspect --format '{{.Id}}' "$from")" = "${base#*@}" ] || { echo "$from is not $base"; exit 1; } ;;
esac
image=v2mac-plugin/$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
docker build --pull=false --platform linux/arm64 ${PROXY:+--build-arg http_proxy=$PROXY --build-arg https_proxy=$PROXY} --build-arg BASE="$from" -f "$dir/Containerfile" -t "$image" "$dir"
rm -rf "dist/$id.image" && mkdir -p "dist/$id.image"
docker save "$image" | tar -x -C "dist/$id.image"
# The plugin's own layers: those after the base's. Each goes in as <n>.tar, applied in order (plan §7).
docker image inspect --format '{{json .RootFS.Layers}}' "$from" > "dist/$id.image/base-layers.json"
python3 - "dist/$id.image" "dist/$id.tar.gz" <<'PY'
import gzip, json, os, shutil, sys, tarfile
folder, out = sys.argv[1:]
manifest = json.load(open(os.path.join(folder, "manifest.json")))[0]
config = json.load(open(os.path.join(folder, manifest["Config"])))
base = json.load(open(os.path.join(folder, "base-layers.json")))
if config["rootfs"]["diff_ids"][:len(base)] != base: sys.exit("the image is not built on the given base")
own = manifest["Layers"][len(base):]
with gzip.GzipFile(out, "wb", mtime=0) as gz, tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as t:
    for n, layer in enumerate(own):
        path = os.path.join(folder, layer)
        with open(path, "rb") as f: zipped = f.read(2) == b"\x1f\x8b"
        if zipped:  # newer Docker saves layers gzipped; the archive is gzipped as a whole instead
            with gzip.open(path) as src, open(path + ".tar", "wb") as dst: shutil.copyfileobj(src, dst)
            path += ".tar"
        info = t.gettarinfo(path, arcname=f"{n}.tar")
        info.mtime, info.uid, info.gid, info.uname, info.gname = 0, 0, 0, "", ""
        with open(path, "rb") as f: t.addfile(info, f)
print(f"{len(own)} own layer(s) of {len(manifest['Layers'])}")
PY
rm -rf "dist/$id.image"
python3 - "$dir/plugin.json" "dist/$id.tar.gz" "$base" "$prefix" "$repo" "$commit" <<'PY'
import hashlib, json, os, sys
src, tar, base, prefix, repo, commit = sys.argv[1:]
m = json.load(open(src))
h = hashlib.sha256()
with open(tar, "rb") as f:
    while chunk := f.read(1 << 20): h.update(chunk)
m["from"] = base
m["source"] = {"repo": repo, "commit": commit}
m["layers"] = [{"url": prefix.rstrip("/") + "/" + os.path.basename(tar), "sha256": h.hexdigest(), "size": os.path.getsize(tar)}]
json.dump(m, open("dist/plugin.json", "w"), indent=1, ensure_ascii=False)
print("dist/plugin.json:", m["id"], m["version"], m["layers"][0]["sha256"])
PY
