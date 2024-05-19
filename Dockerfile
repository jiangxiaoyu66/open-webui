# syntax=docker/dockerfile:1
# 初始化设备类型参数
# 在 docker build 命令中使用 --build-arg="BUILDARG=true" 来使用构建参数
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""

######## WebUI 前端 ########
FROM --platform=$BUILDPLATFORM node:21-alpine3.19 as build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

######## WebUI 后端 ########
FROM python:3.11-slim-bookworm as base

# 使用参数
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL

## 基础设置 ##
ENV ENV=prod \
    PORT=8080 \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL}

## 基础 URL 配置 ##
ENV OPENAI_API_BASE_URL=""

## API Key 和安全配置 ##
ENV OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

# 使用本地捆绑的 LiteLLM 成本图 json 以避免重复的启动连接
ENV LITELLM_LOCAL_MODEL_COST_MAP="True"

#### 其他模型 #########################################################
## whisper TTS 模型设置 ##
ENV WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models"

## RAG 嵌入模型设置 ##
ENV RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models"

## Hugging Face 下载缓存 ##
ENV HF_HOME="/app/backend/data/cache/embedding/models"
#### 其他模型 ##########################################################

WORKDIR /app/backend

ENV HOME /root
RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id

# 安装 Python 依赖项
COPY ./backend/requirements.txt ./requirements.txt

# RUN pip3 install uvicorn && \
#     pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
#     pip install --system -r requirements.txt --no-cache-dir && \
#     python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
#     python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"

RUN pip3 install uvicorn 
# RUN     pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir 
RUN     pip3 install torch torchvision torchaudio --index-url https://pypi.tuna.tsinghua.edu.cn/simple --no-cache-dir 
# RUN    pip3 install --system -r requirements.txt --no-cache-dir
RUN   pip install  -r requirements.txt --no-cache-dir

RUN python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')"

RUN python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"


# 复制构建的前端文件
COPY --from=build /app/build /app/build
COPY --from=build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --from=build /app/package.json /app/package.json

# 复制后端文件
COPY ./backend .

EXPOSE 8080

CMD [ "bash", "start.sh"]
