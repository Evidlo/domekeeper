# Shared paths, sourced by the pipeline scripts.
#   ROOT  this repository (code + the built viewer in app/)
#   WORK  bulky inputs and intermediates: game/, tools/, fullproj/, harness/, data/, renders/
#   PY    Python with numpy, pandas, pyarrow, scipy, pillow, matplotlib
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${DKWORK:-$HOME/tmp/domekeepermaps}
PY=${PY:-$HOME/miniconda3/bin/python}
JOBS=${JOBS:-16}
GODOT=$WORK/tools/Godot_v4.3-stable_linux.x86_64
GDRE=$WORK/tools/gdre_tools.x86_64
export ROOT WORK PY JOBS GODOT GDRE
