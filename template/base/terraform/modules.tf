module "code-server" {
  count   = contains(local.workspace_profile.coder_modules, "code-server") ? data.coder_workspace.me.start_count : 0
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
  folder   = local.project_dir
}

module "git-clone" {
  count    = data.coder_workspace.me.start_count == 1 && local.repository_url != "" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.2"

  agent_id = coder_agent.main.id
  url      = local.repository_url
  base_dir = "/home/coder/projects"
}

module "jetbrains" {
  count   = contains(local.workspace_profile.coder_modules, "jetbrains") ? data.coder_workspace.me.start_count : 0
  source  = "registry.coder.com/coder/jetbrains/coder"
  version = "~> 1.1"

  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = local.project_dir
  tooltip    = "Install JetBrains Toolbox locally before opening this workspace."
}
