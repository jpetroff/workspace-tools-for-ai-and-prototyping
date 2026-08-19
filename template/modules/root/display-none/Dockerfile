# Stable desktop command contract for display-free workspaces.
COPY --chown=coder:coder ./features/root/display-none/.local/ /home/coder/.local/
RUN chmod 0755 \
        /home/coder/.local/bin/workspace-desktop \
        /home/coder/.local/lib/workspace/desktop-backend.sh
