local Diagnostics = require("ts-actions.diagnostics")
local config = require("ts-actions.config")

local M = {}
local m = {}

---@type Diagnostics
m.diagnostics = Diagnostics:new()
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

---@param opts? { severity?: DiagnosticSeverity }
function M.next(opts)
  opts = opts or {}
  m.diagnostics:goto_next_and_show({
    severity = opts.severity or config.severity[vim.bo.filetype],
  })
end

---@param opts? { severity?: DiagnosticSeverity }
function M.prev(opts)
  opts = opts or {}
  m.diagnostics:goto_prev_and_show({
    severity = opts.severity or config.severity[vim.bo.filetype],
  })
end

---@param opts Config
function M.setup(opts)
  config.setup(opts)
end

return M
