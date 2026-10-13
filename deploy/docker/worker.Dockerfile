FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv/worker
COPY apps/crawler-worker/pyproject.toml ./
COPY apps/crawler-worker/worker ./worker
RUN pip install --no-cache-dir --index-url https://mirrors.cloud.tencent.com/pypi/simple --timeout 60 --retries 3 .
CMD ["python", "-m", "worker.main"]
