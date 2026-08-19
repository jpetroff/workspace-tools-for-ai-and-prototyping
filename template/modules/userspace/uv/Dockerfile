# Installing UV Python package manager
RUN /bin/bash -c "$(curl -fsSL https://astral.sh/uv/install.sh)"

COPY --chown=coder:coder ./features/userspace/uv/.local/ /home/coder/.local/
RUN chmod 0755 /home/coder/.local/bin/uvsh
