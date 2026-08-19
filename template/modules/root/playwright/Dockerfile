# Playwright helper dependencies and reference Chromium OS libraries.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv

RUN set -a && \
    . /home/coder/.config/workspace/profile.env && \
    set +a && \
    python3 -m venv /tmp/playwright-system-deps && \
    /tmp/playwright-system-deps/bin/pip install --no-cache-dir \
        "playwright==$PLAYWRIGHT_DEPS_VERSION" && \
    /tmp/playwright-system-deps/bin/playwright install-deps chromium && \
    rm -rf /tmp/playwright-system-deps

COPY --chown=coder:coder ./features/root/playwright/.local/ /home/coder/.local/
RUN chmod 0755 /home/coder/.local/bin/playwright-browser
