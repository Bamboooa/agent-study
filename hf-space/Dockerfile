FROM python:3.12-slim

WORKDIR /app
COPY . /app

# Hugging Face Space 固定监听 7860
ENV PORT=7860
ENV HOST=0.0.0.0
EXPOSE 7860

CMD ["python", "server/server.py"]