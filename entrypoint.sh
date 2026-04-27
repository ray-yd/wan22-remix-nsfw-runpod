#!/bin/bash
set -e

# ════════════════════════════════════════════════
# 設定路徑
# ════════════════════════════════════════════════
VOLUME_DIR="/runpod-volume/models"          # Network Volume 掛載點
COMFY_MODEL_DIR="/ComfyUI/models"           # ComfyUI 模型目錄

# ════════════════════════════════════════════════
# 下載函式：檔案存在則跳過，不存在才下載
# ════════════════════════════════════════════════
download_if_missing() {
    local url="$1"
    local dest="$2"
    local header="$3"   # 可選，用於需要 token 的檔案

    if [ -f "$dest" ]; then
        echo "[SKIP] Already exists: $(basename $dest)"
        return 0
    fi

    echo "[DOWNLOAD] $(basename $dest) ..."
    mkdir -p "$(dirname $dest)"

    if [ -n "$header" ]; then
        wget -q --show-progress --header="$header" "$url" -O "$dest" || {
            echo "[ERROR] Failed to download $(basename $dest)"
            rm -f "$dest"
            exit 1
        }
    else
        wget -q --show-progress "$url" -O "$dest" || {
            echo "[ERROR] Failed to download $(basename $dest)"
            rm -f "$dest"
            exit 1
        }
    fi
    echo "[DONE] $(basename $dest)"
}

# ════════════════════════════════════════════════
# STEP 1：如果 Network Volume 已掛載，使用 symlink
#          讓 ComfyUI 直接讀 Volume 上的模型
# ════════════════════════════════════════════════
if [ -d "$VOLUME_DIR" ]; then
    echo "=== Network Volume detected at $VOLUME_DIR ==="
    echo "=== Linking model directories to Volume ==="

    for subdir in diffusion_models loras clip_vision text_encoders vae; do
        mkdir -p "$VOLUME_DIR/$subdir"
        # 若 ComfyUI 目錄不是 symlink，才進行替換
        if [ ! -L "$COMFY_MODEL_DIR/$subdir" ]; then
            rm -rf "$COMFY_MODEL_DIR/$subdir"
            ln -s "$VOLUME_DIR/$subdir" "$COMFY_MODEL_DIR/$subdir"
            echo "[LINK] $COMFY_MODEL_DIR/$subdir -> $VOLUME_DIR/$subdir"
        fi
    done
else
    echo "=== No Network Volume found, using local model directory ==="
    VOLUME_DIR="$COMFY_MODEL_DIR"
fi

# ════════════════════════════════════════════════
# STEP 2：下載模型（Volume 上已有則自動跳過）
# ════════════════════════════════════════════════
echo "=== Checking / Downloading models ==="

# 啟用 hf_transfer 加速
export HF_HUB_ENABLE_HF_TRANSFER=1

# ── 基礎 Wan2.2 I2V 模型（FP8，公開）
download_if_missing \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" \
    "$VOLUME_DIR/diffusion_models/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors"

download_if_missing \
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors" \
    "$VOLUME_DIR/diffusion_models/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"

# ── FX-FeiHou Remix NSFW LoRA（需要 HF Token）
if [ -z "$HF_TOKEN" ]; then
    echo "[WARN] HF_TOKEN is not set! Skipping NSFW LoRA download."
else
    download_if_missing \
        "https://huggingface.co/FX-FeiHou/wan2.2-Remix/resolve/main/NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors" \
        "$VOLUME_DIR/loras/NSFW/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_fp8_e4m3fn_v3.0.safetensors" \
        "Authorization: Bearer ${HF_TOKEN}"
fi

# ── CLIP Vision
download_if_missing \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" \
    "$VOLUME_DIR/clip_vision/clip_vision_h.safetensors"

# ── Text Encoder
download_if_missing \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" \
    "$VOLUME_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors"

# ── VAE
download_if_missing \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" \
    "$VOLUME_DIR/vae/Wan2_1_VAE_bf16.safetensors"

echo "=== All models ready ==="

# ════════════════════════════════════════════════
# STEP 3：背景啟動 ComfyUI
# ════════════════════════════════════════════════
echo "=== Starting ComfyUI in the background ==="
python /ComfyUI/main.py --listen --use-sage-attention &

# ════════════════════════════════════════════════
# STEP 4：等待 ComfyUI 就緒
# ════════════════════════════════════════════════
echo "=== Waiting for ComfyUI to be ready ==="
max_wait=300    # 首次啟動模型載入可能需要較長時間，設為 5 分鐘
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "=== ComfyUI is ready! (${wait_count}s) ==="
        break
    fi
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "[ERROR] ComfyUI failed to start within ${max_wait}s"
    exit 1
fi

# ════════════════════════════════════════════════
# STEP 5：啟動 RunPod Handler
# ════════════════════════════════════════════════
echo "=== Starting RunPod handler ==="
exec python handler.py