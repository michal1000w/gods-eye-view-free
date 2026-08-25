#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENV="$ROOT/.local-ai/venv"

if [ ! -x "$VENV/bin/mlx_audio.server" ]; then
  printf '%s\n' 'Local voice is not installed. Run: npm run ai:setup' >&2
  exit 1
fi

export HF_HOME="$ROOT/.local-ai/huggingface"
export HF_HUB_OFFLINE=1
export HF_HUB_DISABLE_XET=1
exec "$VENV/bin/mlx_audio.server" --host 127.0.0.1 --port "${LOCAL_MLX_AUDIO_PORT:-8081}"
