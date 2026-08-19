# Tauri v2 native build, WebKitGTK and debugger packages.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gdb \
        gstreamer1.0-libav \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        libayatana-appindicator3-dev \
        libatk1.0-dev \
        libcairo2-dev \
        libgdk-pixbuf-2.0-dev \
        libglib2.0-dev \
        libgtk-3-dev \
        libpango1.0-dev \
        librsvg2-dev \
        libssl-dev \
        libwebkit2gtk-4.1-dev \
        libxdo-dev \
        lldb \
        pkg-config \
        strace

# Linuxbrew is earlier in PATH, but Tauri links against Debian libraries. Put a
# Tauri-specific shim first so both Cargo and `tauri info` use Debian metadata.
RUN install -d -m 0755 /usr/local/lib/tauri/bin && \
    ln -s /usr/bin/pkg-config /usr/local/lib/tauri/bin/pkg-config

ENV PATH=/usr/local/lib/tauri/bin:${PATH} \
    PKG_CONFIG=/usr/bin/pkg-config

# Fail during the image build if the GTK development metadata required by the
# Rust gtk-rs/Tauri crates is unavailable.
RUN /usr/bin/pkg-config --exists \
        atk \
        cairo \
        gdk-3.0 \
        gdk-pixbuf-2.0 \
        gio-2.0 \
        glib-2.0 \
        gobject-2.0 \
        gtk+-3.0 \
        librsvg-2.0 \
        pango \
        webkit2gtk-4.1

COPY --chown=coder:coder ./features/root/tauri/.vscode/ /home/coder/.vscode/
