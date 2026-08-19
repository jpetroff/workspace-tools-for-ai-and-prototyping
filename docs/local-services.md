# Tunnel local Chrome and Figma into a Coder workspace

This is supported. Coder's CLI has reverse SSH forwarding specifically for the
local-to-workspace direction:

```text
Coder workspace                          Local computer
127.0.0.1:9222  ---------------------->  127.0.0.1:9222  Chrome DevTools
127.0.0.1:3845  ---------------------->  127.0.0.1:3845  Figma Desktop MCP
                 encrypted SSH tunnel
```

Coder documents the `coder ssh -R` form as
`remote_port:local_address:local_port`. Its separate `coder port-forward`
command goes the other way, from a workspace to the local computer. See the
[Coder SSH CLI reference](https://coder.com/docs/reference/cli/ssh) and
[Coder port-forward reference](https://coder.com/docs/reference/cli/port-forward).

## Quick start

Install the Coder CLI, log in to the deployment, and enable Figma's desktop MCP
server before starting the tunnel:

```bash
coder login https://coder.example.com
chmod +x ./scripts/tunnel-local-services.sh
./scripts/tunnel-local-services.sh my-workspace
```

The command opens a shell in the workspace. The reverse forwards remain active
while that shell is connected. Exit the shell or press `Ctrl-D` to close them.
The workspace can start its LLM assistant in this shell or in another session.

The script warns when a local service is not listening, but still opens the
tunnel so Chrome or Figma can be started afterward. Run `--help` for options,
including different local/workspace ports and disabling either service.

## Start local Chrome safely

Current Chrome versions require a non-default user data directory when using a
remote debugging port. Start a separate debugging profile instead of exposing a
normal browsing profile. For macOS:

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-profile-coder
```

Linux uses the same arguments with its Chrome executable, for example
`google-chrome`. Google documents both the manual launch form and the matching
`--browser-url=http://127.0.0.1:9222` client setting in the
[Chrome DevTools MCP configuration guide](https://developer.chrome.com/docs/devtools/agents/get-started/configuration).
Chrome 136 and later ignore the debugging switch for the default profile as a
security measure; see Google's
[remote debugging security announcement](https://developer.chrome.com/blog/remote-debugging-port).

Verify from the workspace:

```bash
curl -fsS http://127.0.0.1:9222/json/version
```

An MCP server running in the workspace can connect to the forwarded browser:

```toml
[mcp_servers.chrome-devtools]
command = "bunx"
args = ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://127.0.0.1:9222"]
```

Pin the package version when reproducible configuration is important.

## Enable Figma Desktop MCP

In the local Figma desktop app, open a design, enter Dev Mode, and enable the
desktop MCP server in the inspect panel. Figma documents the current local
endpoint as `http://127.0.0.1:3845/mcp` in its
[desktop server setup guide](https://developers.figma.com/docs/figma-mcp-server/local-server-installation/).

Configure an MCP client running inside the workspace to use the same URL; the
SSH tunnel makes the workspace's loopback port lead to the local Figma app:

```toml
[mcp_servers.figma-desktop]
url = "http://127.0.0.1:3845/mcp"
```

Figma recommends its hosted MCP endpoint for most link-based workflows because
it offers the broadest feature set. The desktop tunnel remains useful for
selection-based workflows and organization-specific requirements.

## Security notes

- Chrome DevTools gives an assistant control of the debugging profile. Use a
  dedicated profile and only connect trusted assistants.
- Any process with access to the workspace loopback ports can use these local
  services while the tunnel is open. Do not publish ports 9222 or 3845 as Coder
  apps or shared ports.
- Closing the SSH session removes the forwards. Close the dedicated Chrome
  instance separately when finished.
- If a workspace port is already occupied, choose another remote port, for
  example `--chrome 9222:19222`, and point the remote MCP client at port 19222.
