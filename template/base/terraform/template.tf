terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.4"
    }
  }
}

variable "docker_socket" {
  type        = string
  default     = ""
  description = "Optional Docker socket URI. Empty uses the provider default."
}

variable "workspace_image" {
  type        = string
  default     = ""
  description = "Optional image override. Empty uses the generated profile image."
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "repository_url" {
  name         = "repository_url"
  display_name = "Git repository"
  description  = "Optional Git URL to clone when this workspace is first created. Leave blank to start with an empty project."
  type         = "string"
  form_type    = "input"
  mutable      = false
  order        = 1
  default      = ""
}

data "coder_parameter" "gpu_render_gid" {
  count        = local.workspace_profile.gpu_enabled ? 1 : 0
  name         = "gpu_render_gid"
  display_name = "GPU render group GID"
  description  = "Numeric host GID owning the selected DRM render node."
  type         = "number"
  form_type    = "input"
  mutable      = false
  order        = 10

  validation {
    min   = 1
    max   = 65535
    error = "Enter the numeric render-node GID from the Docker host."
  }
}

data "coder_parameter" "gpu_render_device" {
  count        = local.workspace_profile.gpu_enabled ? 1 : 0
  name         = "gpu_render_device"
  display_name = "GPU render device"
  description  = "AMD DRM render node on the Docker host."
  type         = "string"
  form_type    = "input"
  mutable      = false
  order        = 11
  default      = local.workspace_profile.render_device_default

  validation {
    regex = "^/dev/dri/renderD[0-9]+$"
    error = "Use a DRM render node such as /dev/dri/renderD128."
  }
}

locals {
  username         = data.coder_workspace_owner.me.name
  image            = var.workspace_image != "" ? var.workspace_image : local.workspace_profile.image
  repository_url   = trimspace(data.coder_parameter.repository_url.value)
  project_dir      = try(module.git-clone[0].repo_dir, "/home/coder/project")
  render_device    = local.workspace_profile.gpu_enabled ? data.coder_parameter.gpu_render_device[0].value : ""
  render_gid       = local.workspace_profile.gpu_enabled ? data.coder_parameter.gpu_render_gid[0].value : 1
  desktop_runtime  = "/home/coder/.local/run/workspace-desktop"
  desktop_state    = "/home/coder/.local/state/workspace-desktop"
  desktop_env_base = merge({
    XDG_CONFIG_HOME = "/home/coder/.config"
    XDG_DATA_HOME   = "/home/coder/.local/share"
    XDG_STATE_HOME  = "/home/coder/.local/state"
    }, local.workspace_profile.desktop_enabled ? {
    DISPLAY                  = ":0"
    XDG_RUNTIME_DIR          = local.desktop_runtime
    DBUS_SESSION_BUS_ADDRESS = "unix:path=${local.desktop_runtime}/dbus-session"
  } : {})
  wayland_env = startswith(local.workspace_profile.display_backend, "wayland-") ? {
    WAYLAND_DISPLAY         = "wayland-1"
    XDG_SESSION_TYPE        = "wayland"
    XDG_CURRENT_DESKTOP     = "sway"
    GDK_BACKEND             = "wayland,x11"
    WLR_BACKENDS            = "headless"
    WLR_HEADLESS_OUTPUTS    = "1"
    WLR_LIBINPUT_NO_DEVICES = "1"
    WLR_RENDERER            = local.workspace_profile.gpu_enabled ? "gles2" : "pixman"
  } : {}
  gpu_env = local.workspace_profile.gpu_enabled ? {
    WLR_RENDER_DRM_DEVICE = local.render_device
  } : {}
  software_env = contains(["wayland-software", "x11-openbox"], local.workspace_profile.display_backend) ? {
    LIBGL_ALWAYS_SOFTWARE = "1"
    GALLIUM_DRIVER        = "llvmpipe"
  } : {}
  playwright_env = contains(local.workspace_profile.features, "playwright") ? {
    PLAYWRIGHT_BROWSERS_PATH = "/home/coder/.cache/ms-playwright"
  } : {}
  preview_env = local.workspace_profile.preview_enabled ? {
    WORKSPACE_PREVIEW_PORT = tostring(local.workspace_profile.preview_port)
  } : {}
  desktop_env = merge(
    local.desktop_env_base,
    local.wayland_env,
    local.gpu_env,
    local.software_env,
    local.playwright_env,
    local.preview_env,
  )
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    "$HOME/.local/bin/workspace-init"
  EOT

  env = merge(local.desktop_env, {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, local.username)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, local.username)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  })

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  dynamic "metadata" {
    for_each = local.workspace_profile.desktop_enabled ? [1] : []
    content {
      display_name = local.workspace_profile.gpu_enabled ? "AMD GPU" : "Renderer"
      key          = "2_renderer"
      script       = "/home/coder/.local/bin/workspace-desktop gpu 2>/dev/null | tail -n 1 || echo unavailable"
      interval     = 60
      timeout      = 5
    }
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

resource "coder_script" "desktop" {
  count              = local.workspace_profile.desktop_autostart ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Start workspace desktop"
  icon               = "/icon/desktop.svg"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 90
  script             = <<-EOT
    set -e
    /home/coder/.local/bin/workspace-desktop start
    /home/coder/.local/bin/workspace-desktop health
  EOT
}

resource "coder_app" "desktop" {
  count        = local.workspace_profile.desktop_enabled ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "workspace-desktop"
  display_name = "Workspace Desktop"
  icon         = "/icon/desktop.svg"
  order        = 2
  share        = "owner"
  url          = "http://localhost:${local.workspace_profile.novnc_port}/"
  subdomain    = true

  dynamic "healthcheck" {
    for_each = local.workspace_profile.desktop_autostart ? [1] : []
    content {
      url       = "http://localhost:${local.workspace_profile.novnc_port}/"
      interval  = 3
      threshold = 30
    }
  }
}

resource "coder_app" "preview" {
  count        = local.workspace_profile.preview_enabled ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Preview"
  icon         = "/icon/code.svg"
  order        = 3
  share        = "owner"
  url          = "http://localhost:${local.workspace_profile.preview_port}/"
  subdomain    = true
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.name}-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = local.image
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = [
    "sh",
    "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal"),
  ]

  env = concat(
    ["CODER_AGENT_TOKEN=${coder_agent.main.token}"],
    [for key, value in local.desktop_env : "${key}=${value}"],
  )

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  dynamic "devices" {
    for_each = local.workspace_profile.gpu_enabled ? [1] : []
    content {
      host_path      = local.render_device
      container_path = local.render_device
      permissions    = "rwm"
    }
  }

  group_add = local.workspace_profile.gpu_enabled ? [tostring(local.render_gid)] : []
  shm_size  = local.workspace_profile.shm_size_mb
  init      = true

  dynamic "capabilities" {
    for_each = local.workspace_profile.native_debug ? [1] : []
    content {
      add = ["SYS_PTRACE"]
    }
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
