FROM nginx:latest AS base

RUN apt-get update && \
	apt-get install -y --no-install-recommends iptables iproute2 \
	tcpdump iputils-ping curl && \
	rm -rf /var/lib/apt/lists/*

COPY default.conf /etc/nginx/conf.d/default.conf
COPY 99-iptables.sh /docker-entrypoint.d/99-iptables.sh
RUN chmod +x /docker-entrypoint.d/99-iptables.sh

ARG BLOCK_LAN=0
ENV BLOCK_LAN=$BLOCK_LAN

FROM base AS debug
RUN apt-get update && \
	apt-get install -y --no-install-recommends tcpdump iputils-ping curl dnsutils && \
	rm -rf /var/lib/apt/lists/*
