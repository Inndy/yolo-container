FROM node:22-bookworm-slim

# iproute2: `ip route` for the default-route rewrite. getent comes from libc-bin.
RUN apt-get update && \
	apt-get install -y --no-install-recommends iproute2 ca-certificates && \
	rm -rf /var/lib/apt/lists/*

# Pure-JS deps (ws, @anthropic-ai/tokenizer) — no build toolchain needed.
# Default tracks the latest npm release. CCXRAY_CACHEBUST (a timestamp fed by the
# Makefile when tracking 'latest') invalidates this layer so the build re-pulls.
ARG CCXRAY_VERSION=latest
ARG CCXRAY_CACHEBUST=0
RUN npm install -g ccxray@${CCXRAY_VERSION}

ENV HOME=/root
ENV PROXY_PORT=5577

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["ccxray", "--no-browser"]
