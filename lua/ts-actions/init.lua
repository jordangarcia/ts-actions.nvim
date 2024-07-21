local M = {}
local m = {}

local Diagnostics = require("ts-actions.diagnostics")
local lsp = require("ts-actions.lsp")

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
  register_ui_select = false,
}

--- Show a selection prompt with the code actions available for the cursor
--- position.
function M.code_action()
  local code_actions = lsp.code_action()
  if code_actions == nil or vim.tbl_isempty(code_actions) then
    return vim.notify("No code actions available", vim.log.levels.INFO)
  end
  M.select(code_actions, {
    prompt = "Code Actions:",
    format_item = function(item)
      return item.title
    end,
    relative = "cursor",
  }, lsp.execute_command)
end

--- Show a selection prompt with the code actions available for the visual
--- selection range.
function M.range_code_action()
  local code_actions = lsp.range_code_action()
  if code_actions == nil or vim.tbl_isempty(code_actions) then
    return vim.notify("No code actions available", vim.log.levels.WARN)
  end
  local opts = {
    prompt = "Code Actions:",
    format_item = function(item)
      return item.title
    end,
    relative = "cursor",
  }
  M.select(code_actions, opts, lsp.execute_command)
end

--- Prompts the user to pick from a list of items, allowing arbitrary (potentially asynchronous)
--- work until `on_choice`.
---
--- Example:
---
--- ```lua
--- vim.ui.select({ 'tabs', 'spaces' }, {
---     prompt = 'Select tabs or spaces:',
---     format_item = function(item)
---         return "I'd like to choose " .. item
---     end,
--- }, function(choice)
---     if choice == 'spaces' then
---         vim.o.expandtab = true
---     else
---         vim.o.expandtab = false
---     end
--- end)
--- ```
---

function M.next(opts)
  local opts = opts or {}
  local severity = opts.severity or m.diagnostics.opts.severity[vim.bo.filetype]
  m.diagnostics:goto_next_and_show({ severity = severity })
end

---@param opts Config
function M.setup(opts)
  local config = vim.tbl_deep_extend("force", m.defaults, opts or {})
  -- if m.config.register_ui_select then vim.ui.select = M.select end
  if type(config.keys) == "string" then
    config.keys =
      vim.split(config.keys --[=[@as string]=], "", { trimempty = true })
  end
  m.diagnostics = Diagnostics:new(config)
end

return M
