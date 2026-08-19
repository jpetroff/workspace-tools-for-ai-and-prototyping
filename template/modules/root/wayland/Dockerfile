# Headless Sway, XWayland, WayVNC and portal stack.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        foot \
        libegl1 \
        libgbm1 \
        libgl1-mesa-dri \
        libgles2 \
        sway \
        waffle-utils \
        wayvnc \
        x11-utils \
        xdg-desktop-portal-gtk \
        xdg-desktop-portal-wlr \
        xdg-utils \
        xwayland

COPY --chown=coder:coder ./features/root/wayland/.config/ /home/coder/.config/
COPY --chown=coder:coder ./features/root/wayland/.local/ /home/coder/.local/
RUN chmod 0755 \
        /home/coder/.local/bin/workspace-desktop \
        /home/coder/.local/bin/workspace-status \
        /home/coder/.local/lib/workspace/desktop-backend.sh
