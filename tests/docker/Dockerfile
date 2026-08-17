# Shared test image for dotfiles installation testing.
# Build with:
#   docker build --build-arg UBUNTU_VERSION=22.04 -t dotfiles-test:ubuntu2204 -f Dockerfile .
#   docker build --build-arg UBUNTU_VERSION=24.04 -t dotfiles-test:ubuntu2404 -f Dockerfile .

ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create a non-root user with passwordless sudo
# libkf5config-bin provides kwriteconfig5/kreadconfig5, which the `kde` suite
#   needs to exercise the global-shortcut merge. It is ~1MB, unlike the full
#   plasma-desktop.
# fontconfig provides fc-cache/fc-list. Without it the font steps take their
#   "fontconfig absent" fallback branch, so the real cache-rebuild path would
#   never be tested.
# iputils-ping is deliberately NOT installed: lib/common.sh check_internet must
#   work without it (it probes via curl/wget/DNS instead). Adding ping here
#   would hide a regression in that fallback chain.
RUN useradd -m -s /bin/bash testuser && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        sudo git curl wget ca-certificates locales \
        libkf5config-bin fontconfig && \
    locale-gen en_US.UTF-8 && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    rm -rf /var/lib/apt/lists/*

USER testuser
WORKDIR /home/testuser

# Copy the dotfiles repo into the container
COPY --chown=testuser:testuser . /home/testuser/my-dotfiles

WORKDIR /home/testuser/my-dotfiles

CMD ["/bin/bash"]
