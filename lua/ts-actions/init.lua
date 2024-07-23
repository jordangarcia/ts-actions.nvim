local Config = require("ts-actions.config")
local Diagnostics = require("ts-actions.diagnostics")

local M = {}
local m = {}

---@type Diagnostics
m.diagnostics = nil
---@type string[]
m.keys = {}
---@type Config
m.defaults = {
  dismiss_keys = { "<esc>", "<c-c>", "q" },
  keys = "wertyuiopasdfghlzxcvbnm",
  override_function = function(_) end,
  priority = {},
  severity = {},
}

function M.next(opts)
  opts = opts or {}
  local severity = opts.severity or Config.config.severity[vim.bo.filetype]
  m.diagnostics:goto_next_and_show({ severity = severity })
end

---@param opts Config
function M.setup(opts)
  Config.setup(opts)

  m.diagnostics = Diagnostics:new()
end

return M
