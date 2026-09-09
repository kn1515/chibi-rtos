"""Copy one FIT file to an already mounted SD boot partition; never format it."""
import os
from pathlib import Path
import shutil
import sys

value = os.environ.get("CHIBI_SD_DIR", "")
if not value:
    sys.exit("Specify SD_DIR=/path/to/mounted/boot-partition")
destination = Path(value).resolve()
if not destination.is_dir() or not os.path.ismount(destination):
    sys.exit("SD_DIR must be the mount point of an already mounted SD boot partition")
if not (destination / "fip.bin").is_file():
    sys.exit("fip.bin was not found: select the existing Milk-V Duo boot partition")
source = Path(__file__).resolve().parents[1] / "build/milkv/chibi-os.itb"
output = destination / source.name
if output.is_symlink():
    sys.exit("Refusing to overwrite a symlink at the destination")
with source.open("rb") as src, output.open("wb") as dst:
    shutil.copyfileobj(src, dst)
    dst.flush()
    os.fsync(dst.fileno())
print(f"Copied {output}. Safely unmount the SD card before removing it.")
