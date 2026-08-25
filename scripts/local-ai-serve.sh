#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENV="$ROOT/.local-ai/venv"
MODEL="${LOCAL_MLX_MODEL:-Qwen/Qwen3-4B-MLX-4bit}"

if [ ! -x "$VENV/bin/mlx_lm.server" ]; then
  printf '%s\n' 'Local MLX is not installed. Run: npm run ai:setup' >&2
  exit 1
fi

export HF_HOME="$ROOT/.local-ai/huggingface"
# Setup owns downloads. Serving offline makes startup deterministic and fails
# clearly if setup has not completed instead of hanging behind a lazy download.
export HF_HUB_OFFLINE=1
export HF_HUB_DISABLE_XET=1
exec "$VENV/bin/mlx_lm.server" --model "$MODEL" --host 127.0.0.1 --port "${LOCAL_MLX_PORT:-8080}"
