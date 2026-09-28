# Provide an Ubuntu development environment for the dev container.
FROM ubuntu:26.04

# Install the latest rolling Sun release and its runtime dependencies, plus the
# SSH and GitHub clients so the mounted host ~/.ssh and ~/.config/gh folders
# let git and gh work inside the container.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl git gh openssh-client g++ make perl \
        libzstd-dev libjitterentropy3-dev \
    && curl --fail --location --retry 3 \
        https://github.com/namo-robotics/sun/releases/download/dev/sun_0.dev_amd64.deb \
        -o /tmp/sun.deb \
    && chmod 0644 /tmp/sun.deb \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/sun.deb \
    && rm -f /tmp/sun.deb \
    && rm -rf /var/lib/apt/lists/* \
    && sun --version \
    && if ! id -u ubuntu >/dev/null 2>&1; then useradd --create-home --shell /bin/bash ubuntu; fi

ENV PATH="/workspace/.ci/musl/x86_64-linux-musl-cross/bin:/workspace/.ci/musl/aarch64-linux-musl-cross/bin:${PATH}"

USER ubuntu
WORKDIR /workspace
CMD ["sleep", "infinity"]
