# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Clone ComfyUI repository at specific commit
RUN git clone https://github.com/zdaar/ComfyUI.git /comfyui && \
    cd /comfyui && \
    git checkout ec28cd91363a4de6c0e7a968aba61fd035a550b9

# Clone ComfyUI-GGUF repository at specific commit
RUN git clone https://github.com/zdaar/ComfyUI-GGUF /comfyui/custom_nodes/ComfyUI-GGUF && \
    cd /comfyui/custom_nodes/ComfyUI-GGUF && \
    git checkout abe5c6a6c90a3f8a53a097614bf749de506c6df7 && \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# Clone ComfyUI-KJNodes repository at specific commit
RUN git clone https://github.com/zdaar/ComfyUI-KJNodes /comfyui/custom_nodes/ComfyUI-KJNodes && \
    cd /comfyui/custom_nodes/ComfyUI-KJNodes && \
    git checkout 326d5945b711e6e161de83cd2a7fb3ba3839560a && \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# Clone ComfyUI_Comfyroll_CustomNodes repository at specific commit
RUN git clone https://github.com/zdaar/ComfyUI_Comfyroll_CustomNodes /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && \
    cd /comfyui/custom_nodes/ComfyUI_Comfyroll_CustomNodes && \
    git checkout d78b780ae43fcf8c6b7c6505e6ffb4584281ceca && \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi    

# Clone ComfyUI-Various repository at specific commit
RUN git clone https://github.com/zdaar/comfyui-various /comfyui/custom_nodes/comfyui-various && \
    cd /comfyui/custom_nodes/comfyui-various && \
    git checkout cc66b62c0861314a4952eb96a6ae330f180bf6a1 && \
    if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install ComfyUI dependencies
RUN pip3 install --upgrade --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && \
    pip3 install --upgrade --no-cache-dir -r requirements.txt


# Install runpod
RUN pip3 install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add the start and the handler
ADD src/start.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

# Download checkpoints/vae/LoRA to include in image based on model type
RUN if [ "$MODEL_TYPE" = "sdxl" ]; then \
      wget -O models/checkpoints/sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors && \
      wget -O models/vae/sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors && \
      wget -O models/vae/sdxl-vae-fp16-fix.safetensors https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors; \
    elif [ "$MODEL_TYPE" = "sd3" ]; then \
      wget --header="Authorization: Bearer ${HUGGINGFACE_ACCESS_TOKEN}" -O models/checkpoints/sd3_medium_incl_clips_t5xxlfp8.safetensors https://huggingface.co/stabilityai/stable-diffusion-3-medium/resolve/main/sd3_medium_incl_clips_t5xxlfp8.safetensors; \
    elif [ "$MODEL_TYPE" = "flux-schell" ]; then \
      wget -O models/checkpoints/flux1-schnell-fp8.safetensors https://huggingface.co/Comfy-Org/flux1-schnell/resolve/main/flux1-schnell-fp8.safetensors; \
    fi

# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start the container
CMD /start.sh
