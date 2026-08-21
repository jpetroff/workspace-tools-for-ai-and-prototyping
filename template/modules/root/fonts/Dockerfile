# Redistributable system fonts for prototypes and browser automation.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fontconfig \
        fonts-firacode \
        fonts-liberation \
        fonts-noto-color-emoji \
        fonts-noto-core

# Install every font placed anywhere in this feature. fc-scan filters out the
# Dockerfile, licenses and documentation without restricting supported formats.
COPY ./features/root/fonts/ /tmp/workspace-fonts/
RUN install -d -m 0755 /usr/local/share/fonts/workspace && \
    cd /tmp/workspace-fonts && \
    find . -type f -exec sh -c \
        'for source do \
            if fc-scan "$source" >/dev/null 2>&1; then \
                install -D -m 0644 "$source" \
                    "/usr/local/share/fonts/workspace/${source#./}"; \
            fi; \
        done' sh {} + && \
    fc-cache -f && \
    rm -rf /tmp/workspace-fonts

COPY --chown=coder:coder ./features/root/fonts/.local/ /home/coder/.local/
RUN chmod 0755 /home/coder/.local/bin/workspace-font
