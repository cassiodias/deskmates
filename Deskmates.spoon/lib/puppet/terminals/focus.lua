-- Brings forward the terminal running a session: its exact iTerm tab when known, otherwise the terminal app
-- (by the TERM_PROGRAM the hook saw) and the window whose title names the project folder.

local TERMINALS = {
  ["iTerm.app"] = "com.googlecode.iterm2",
  Apple_Terminal = "com.apple.Terminal",
  ghostty = "com.mitchellh.ghostty",
  WezTerm = "com.github.wez.wezterm",
  WarpTerminal = "dev.warp.Warp-Stable",
  vscode = "com.microsoft.VSCode",
  Hyper = "co.zeit.hyper",
  Tabby = "org.tabby",
  zed = "dev.zed.Zed",
}

-- Returns the terminals helper a harness's focus function receives:
--   terminals.focus(session)       the session's terminal: its iTerm tab, or its terminal app's window
--   terminals.app(bundle, folder)  app bundle id `bundle` brought forward, at its window whose title has `folder`;
--                                  for an agent that runs inside its own app rather than a terminal
return function(iterm)
  local terminals = {}

  function terminals.app(bundle, folder)
    hs.application.launchOrFocusByBundleID(bundle)
    local app = hs.application.get(bundle)
    if not app or (folder or "") == "" then return end
    for _, win in ipairs(app:allWindows()) do
      if (win:title() or ""):find(folder, 1, true) then
        win:focus()
        return
      end
    end
  end

  function terminals.focus(s)
    if s.app == "iTerm.app" and s.tty and iterm:select(s.tty) then return end
    local bundle = TERMINALS[s.app or ""]
    if bundle then terminals.app(bundle, s.folder) end
  end

  return terminals
end
