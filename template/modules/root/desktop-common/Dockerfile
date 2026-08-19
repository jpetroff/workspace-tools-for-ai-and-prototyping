# Shared VNC, noVNC, D-Bus and browser-font packages.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        dbus \
        dbus-x11 \
        fonts-liberation \
        fonts-noto-color-emoji \
        novnc \
        websockify \
        xauth

# Seed package-owned noVNC files, then apply the feature's visible defaults.
RUN install -d -m 0755 -o coder -g coder \
        /home/coder/.local/bin \
        /home/coder/.local/share/novnc && \
    cp -a /usr/share/novnc/. /home/coder/.local/share/novnc/ && \
    cp /usr/share/novnc/utils/novnc_proxy /home/coder/.local/bin/novnc_proxy && \
    chown -R coder:coder \
        /home/coder/.local/bin/novnc_proxy \
        /home/coder/.local/share/novnc && \
    chmod 0755 /home/coder/.local/bin/novnc_proxy

COPY --chown=coder:coder ./features/root/desktop-common/.local/ /home/coder/.local/
