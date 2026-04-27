FROM wlsdml1114/engui_genai-base_blackwell:1.1 as runtime

# ── 加速 HuggingFace 下載（啟用 hf_transfer）
RUN pip install -U "huggingface_hub[hf_transfer]"
RUN pip install runpod websocket-client

WORKDIR /

# ── 安裝 ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && \
    pip install -r requirements.txt

# ── 安裝所有 Custom Nodes（合併成單一 RUN，減少 image 層數）
RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && pip install -r requirements.txt && cd .. && \
    \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && pip install -r requirements.txt && cd .. && \
    \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    cd ComfyUI-VideoHelperSuite && pip install -r requirements.txt && cd .. && \
    \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper && \
    cd ComfyUI-WanVideoWrapper && pip install -r requirements.txt && cd .. && \
    \
    git clone https://github.com/orssorbit/ComfyUI-wanBlockswap && \
    \
    git clone https://github.com/eddyhhlure1Eddy/IntelligentVRAMNode && \
    \
    git clone https://github.com/eddyhhlure1Eddy/ComfyUI-AdaptiveWindowSize && \
    cd ComfyUI-AdaptiveWindowSize/ComfyUI-AdaptiveWindowSize && \
    mv * ../ && cd /

# ── 建立模型目錄（Volume 掛載後會覆蓋，這裡只是預建結構）
RUN mkdir -p \
    /ComfyUI/models/diffusion_models \
    /ComfyUI/models/loras/NSFW \
    /ComfyUI/models/clip_vision \
    /ComfyUI/models/text_encoders \
    /ComfyUI/models/vae

# ── 複製應用程式檔案
COPY . .
COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]