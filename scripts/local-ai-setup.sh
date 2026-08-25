#!/bin/sh
set -eu

# The Kokoro local-voice dependencies support Python 3.10–3.12. Override this
# when your default `python3` is newer (for example: PYTHON_BIN=python3.12).
PYTHON_BIN="${PYTHON_BIN:-python3}"
MODEL="${LOCAL_MLX_MODEL:-Qwen/Qwen3-4B-MLX-4bit}"
STT_MODEL="${LOCAL_MLX_STT_MODEL:-mlx-community/whisper-large-v3-turbo-asr-fp16}"
TTS_MODEL="${LOCAL_MLX_TTS_MODEL:-mlx-community/Kokoro-82M-bf16}"
# MLX Kokoro weights and its voice packs are published separately. The server
# loads a selected voice lazily from this upstream repository.
KOKORO_VOICE_MODEL="prince-canuma/Kokoro-82M"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENV="$ROOT/.local-ai/venv"
HF_HOME="$ROOT/.local-ai/huggingface"

python_supported() {
  "$1" - <<'PY' >/dev/null 2>&1
import sys
if not ((3, 10) <= sys.version_info[:2] <= (3, 12)):
    raise SystemExit('Local voice needs Python 3.10–3.12; rerun with PYTHON_BIN=python3.12')
PY
}

# macOS often points `python3` at a newer Homebrew interpreter while a
# compatible 3.12 is installed alongside it. Choose the latter automatically
# so `npm run ai:setup` works without a shell-specific override.
if ! python_supported "$PYTHON_BIN"; then
  for candidate in python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1 && python_supported "$candidate"; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
fi

if ! python_supported "$PYTHON_BIN"; then
  printf '%s\n' 'Local voice needs Python 3.10–3.12. Install one, then rerun npm run ai:setup.' >&2
  exit 1
fi

if [ -x "$VENV/bin/python" ] && ! "$VENV/bin/python" - <<'PY'
import sys
raise SystemExit(0 if sys.version_info[:2] <= (3, 12) else 1)
PY
then
  printf '%s\n' "Existing $VENV uses Python 3.13. Remove only that virtual environment, then rerun setup:" >&2
  printf '%s\n' "rm -rf .local-ai/venv && PYTHON_BIN=$PYTHON_BIN npm run ai:setup" >&2
  exit 1
fi

"$PYTHON_BIN" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade mlx-lm 'mlx-audio[server]' 'misaki[en]'
# Avoid `spacy download`, which first fetches a compatibility index from a
# separate host. This official, version-pinned wheel is more reliable in a
# clean local setup and remains fully contained in the project virtualenv.
"$VENV/bin/python" -m pip install --upgrade 'https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl'
# Download before starting the server. Disabling hf-xet avoids its misleading
# indeterminate progress display and leaves a resumable ordinary HTTP download.
HF_HOME="$HF_HOME" HF_HUB_DISABLE_XET=1 HF_HUB_DISABLE_PROGRESS_BARS=1 "$VENV/bin/python" - <<PY
from pathlib import Path
import shutil
from huggingface_hub import snapshot_download

paths = {}
for model in ("$MODEL", "$STT_MODEL", "$TTS_MODEL"):
    path = Path(snapshot_download(repo_id=model))
    weights = list(path.glob('*.safetensors')) + list(path.glob('*.npz'))
    if not weights:
        raise SystemExit(f'No model weights found in {path}')
    paths[model] = path
    print(f'Downloaded and verified {model} at {path}')

# The MLX model supplies the synthesis weights; the selected API voice lives in
# this companion repository. Cache it during setup so the loopback server stays
# fully offline at runtime.
voice_path = Path(snapshot_download(repo_id="$KOKORO_VOICE_MODEL"))
if not (voice_path / 'voices' / 'af_heart.safetensors').exists():
    raise SystemExit(f'Kokoro voice pack af_heart was not found in {voice_path}')
print(f'Downloaded and verified Kokoro voice packs at {voice_path}')

# The legacy compact Whisper conversion contains MLX weights but not the
# Hugging Face processor. Keep this compatibility path for explicit overrides;
# the default Whisper Large v3 Turbo package is self-contained.
if "$STT_MODEL" == 'mlx-community/whisper-small.en-mlx':
    processor_files = [
        'preprocessor_config.json', 'tokenizer.json', 'tokenizer_config.json',
        'special_tokens_map.json', 'added_tokens.json', 'normalizer.json',
        'generation_config.json', 'vocab.json', 'merges.txt',
    ]
    source = Path(snapshot_download('openai/whisper-small.en', allow_patterns=processor_files))
    target = paths["$STT_MODEL"]
    for name in processor_files:
        if (source / name).exists():
            shutil.copy2(source / name, target / name)
    if not (target / 'preprocessor_config.json').exists():
        raise SystemExit('Whisper processor download did not provide preprocessor_config.json')
    print(f'Installed Whisper processor files in {target}')
PY

printf '%s\n' "Start it with: npm run ai:serve (then run npm run dev in a second terminal)"
