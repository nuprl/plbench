FROM python:3.13-slim

RUN pip install --no-cache-dir \
        cloudpickle \
        pytest \
        pytest-asyncio \
        typing-extensions

WORKDIR /app

COPY actor.py /app/actor.py
