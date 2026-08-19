# A minimal example showing direct configuration and feature fragments.
RUN apt-get update && \
    apt-get install -y --no-install-recommends tree

COPY --chown=coder:coder ./features/root/sample-customization/.config/ /home/coder/.config/
