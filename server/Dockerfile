# Qatys API — image for Render (or any Docker host).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app
COPY seed.py .

# Never run as root inside the container.
RUN useradd --create-home --uid 10001 qatys
USER qatys

# Render sets PORT. --proxy-headers: the client IP for the login rate limit
# comes from Render's proxy, not from the proxy itself.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
