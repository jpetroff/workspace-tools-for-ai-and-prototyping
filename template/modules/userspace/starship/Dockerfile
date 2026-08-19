# Install Starship without invalidating its install layer when config changes.
RUN curl -fsSL https://starship.rs/install.sh | /bin/sh -s -- -y -b "/home/coder/.local/bin"

COPY --chown=coder:coder ./features/userspace/starship/.config/starship.toml \
    /home/coder/.config/starship.toml
