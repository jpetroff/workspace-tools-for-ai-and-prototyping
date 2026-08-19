# Xvfb/Openbox desktop with x11vnc and software GL.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mesa-utils \
        openbox \
        x11-utils \
        x11vnc \
        xterm \
        xvfb

COPY --chown=coder:coder ./features/root/x11-openbox/.config/ /home/coder/.config/
COPY --chown=coder:coder ./features/root/x11-openbox/.local/ /home/coder/.local/
RUN chmod 0755 \
        /home/coder/.config/openbox/autostart \
        /home/coder/.local/bin/workspace-desktop \
        /home/coder/.local/lib/workspace/desktop-backend.sh
