# Core command-line and native build tools.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash-completion \
        bat \
        build-essential \
        clang \
        cmake \
        file \
        fzf \
        gcc \
        git \
        gpg \
        jq \
        less \
        lsof \
        net-tools \
        ninja-build \
        openssh-client \
        pkg-config \
        procps \
        ripgrep \
        unzip \
        wget

RUN if [ -x /usr/bin/batcat ]; then ln -sf /usr/bin/batcat /usr/bin/bat; fi
