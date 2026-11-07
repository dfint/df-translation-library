FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG ZIG_VERSION=0.17.1
ARG ZLINT_VERSION=0.10.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLo /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz --strip-components=1 -C /opt/zig \
    && ln -s /opt/zig/zig /usr/local/bin/zig \
    && curl -fsSLo /usr/local/bin/zlint "https://github.com/DonIsaac/zlint/releases/download/v${ZLINT_VERSION}/zlint-linux-x86_64" \
    && chmod +x /usr/local/bin/zlint \
    && rm /tmp/zig.tar.xz
