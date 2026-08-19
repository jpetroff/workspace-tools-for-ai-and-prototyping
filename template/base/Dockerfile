FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    HOME=/home/coder \
    XDG_CONFIG_HOME=/home/coder/.config \
    XDG_DATA_HOME=/home/coder/.local/share \
    XDG_STATE_HOME=/home/coder/.local/state \
    PATH=/home/coder/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}

# Install only the packages required by every workspace. Feature packages stay
# in their own Dockerfile slices so Docker can cache them independently.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        locales \
        sudo \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

# Mandatory user creation section.
RUN useradd --uid 1000 --user-group --create-home --shell /bin/bash coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder && \
    install -d -m 1777 /tmp/.X11-unix && \
    install -d -m 0755 -o coder -g coder \
        /home/coder/.cache \
        /home/coder/.config/workspace \
        /home/coder/.local/bin \
        /home/coder/.local/lib/workspace \
        /home/coder/.local/share \
        /home/coder/.local/state \
        /home/coder/project \
        /home/coder/projects && \
    install -d -m 0700 -o coder -g coder \
        /home/coder/.local/run \
        /home/coder/.local/run/workspace-desktop

# Install the complete, image-owned shell files. /etc/skel is intentionally
# ignored; a new workspace receives these files as the initial /home volume.
COPY --chown=coder:coder ./base/.bashrc ./base/.profile /home/coder/
COPY --chown=coder:coder ./base/bash_config /home/coder/.config/bash_config
COPY --chown=coder:coder ./base/profile.env /home/coder/.config/workspace/profile.env
COPY --chown=coder:coder ./base/scripts /home/coder/.config/workspace/scripts
COPY --chown=coder:coder ./base/init /home/coder/.config/workspace/init
COPY --chown=coder:coder ./base/workspace-init /home/coder/.local/bin/workspace-init
RUN chmod 0755 /home/coder/.local/bin/workspace-init \
        /home/coder/.config/workspace/init

# ----------------------
# Root features are inserted below in profile declaration order.
# ----------------------
# {{ROOT_FEATURES}}

RUN chown -R coder:coder /home/coder

USER coder
WORKDIR $HOME

# ----------------------
# Userspace features are inserted below in profile declaration order.
# ----------------------
# {{USERSPACE_FEATURES}}

# Apt metadata is retained across root feature layers and cleared only after
# every feature has installed its packages.
USER root
RUN rm -rf /var/lib/apt/lists/*

USER coder
WORKDIR $HOME

# Coder replaces this command with the agent init script.
CMD ["/bin/bash"]
