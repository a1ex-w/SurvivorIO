FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    libgl1 \
    libgles2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY build/server/ .

EXPOSE 3131

CMD ["./surviveIO.x86_64", "--headless"]
