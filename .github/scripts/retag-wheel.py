#!/usr/bin/env python3
"""Retag wheels: linux_<arch> -> android_<api>_<abi>.

O wheel tooling do runner (x86_64) nao conhece a plataforma 'android', entao
bdist_wheel so consegue produzir wheels linux_<arch>. O python DEFAULT do Termux
(3.14+) reporta plataforma android-<api>-<abi> e so aceita wheels android_*.
Este script reescreve o Tag no .dist-info/WHEEL e renomeia o arquivo .whl,
convertendo o platform tag. O conteudo (.so aarch64) nao muda — so o metadata.

Uso: retag-wheel.py <dist_dir> <new_platform>   ex: retag-wheel.py dist android_24_arm64_v8a
"""
import sys, zipfile, shutil, os


def retag(path, newplat):
    base = os.path.basename(path)
    with zipfile.ZipFile(path) as zin:
        names = zin.namelist()
        wheel_entry = [n for n in names if n.endswith(".dist-info/WHEEL")][0]
        data = zin.read(wheel_entry).decode().splitlines()
    newlines = []
    for line in data:
        if line.startswith("Tag:"):
            parts = line[4:].strip().split("-")
            if len(parts) >= 3:
                parts[-1] = newplat            # platform e sempre o ultimo segmento
                line = "Tag: " + "-".join(parts)
        newlines.append(line)
    tmp = path + ".new"
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            d = zin.read(item.filename)
            if item.filename == wheel_entry:
                d = ("\n".join(newlines) + "\n").encode()
            zout.writestr(item, d)
    shutil.move(tmp, path)
    stem, _plat = base.rsplit("-", 1)
    newname = stem + "-" + newplat + ".whl"
    os.rename(path, os.path.join(os.path.dirname(path), newname))
    print(f"retag: {base} -> {newname}")


if __name__ == "__main__":
    dist_dir, newplat = sys.argv[1], sys.argv[2]
    wheels = sorted(f for f in os.listdir(dist_dir) if f.endswith(".whl"))
    if not wheels:
        print("nenhum wheel para retagar")
        sys.exit(0)
    for w in wheels:
        retag(os.path.join(dist_dir, w), newplat)
