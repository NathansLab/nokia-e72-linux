# SPDX-License-Identifier: MIT
# native arm64 image for the E72 kernel build (gcc-arm-linux-gnueabi), dtc and the Alpine rootfs step
FROM --platform=linux/arm64 debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libc6-dev gcc-arm-linux-gnueabi make bc bison flex libssl-dev libelf-dev device-tree-compiler \
    cpio curl python3 kmod xz-utils gzip ca-certificates perl rsync git && rm -rf /var/lib/apt/lists/*
