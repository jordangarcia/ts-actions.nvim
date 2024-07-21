local event = require("nui.utils.autocmd").event
local Line = require("nui.line")
local LineBuffer = require("ts-actions.line-buffer")
local Popup = require("nui.popup")
local Text = require("nui.text")
local keys = require("ts-actions.keys")
local lsp2 = require("ts-actions.lsp")
local utils = require("ts-actions.utils")

---@class Diagnostics
---@field popup any
---@field keymaps {key: string, mode: string[], buf: number}[]
---@field autocmd_group number|nil
---@field opts ParsedConfig
local Diagnostics = {}
Diagnostics.__index = Diagnostics

---@param opts ParsedConfig
function Diagnostics:new(opts)
  local self = setmetatable({}, Diagnostics)
  self.opts = opts
  self.popup = nil
  self.keymaps = {}
  self.autocmd_group = nil
  print(vim.inspect(self.opts))
  return self
end

---@return ActionOption[]
function Diagnostics:get_code_actions()
  local code_actions = lsp2.code_action() or {}
  local used_keys = {}
  ---@type ActionOption[]
  local options = {}

  for i, action in ipairs(code_actions) do
    if action.title then
      ---@type ActionOption
      local option =
        { action = action, order = 0, key = "", title = action.title }
      print("priorities" .. vim.inspect(self.opts.priority[vim.bo.filetype]))
      local match = assert(
        keys.get_action_config({
          title = option.title,
          priorities = self.opts.priority[vim.bo.filetype],
          ---@type string[]
          valid_keys = self.opts.keys,
          invalid_keys = used_keys,
          override_function = function(_) end,
        }),
        'Failed to find a key to map to "' .. option.title .. '"'
      )
      option.key = match.key
      option.order = match.order
      options[i] = option
    end
  end

  table.sort(options, function(a, b)
    return a.order > b.order
  end)

  if self.opts.filter_function then
    options = vim.tbl_filter(function(option)
      print("filtering" .. vim.inspect(option.action))
      return self.opts.filter_function(option.action)
    end, options)
  end

  return options
end

---@param diagnostic Diagnostic
---@param highlight string
---@param actions ActionOption[]
---@return LineBuffer
local function make_diagnostic_lines(diagnostic, highlight, actions)
  local linebuffer = LineBuffer:new({ max_width = 80, padding = 1 })

  linebuffer:append(diagnostic.message, highlight)
  local diagnostic_str = utils.diagnostic_source_str(diagnostic)
  -- Add source and code if available
  if diagnostic_str then
    linebuffer:append(" " .. diagnostic_str, "Comment")
  end

  if #actions == 0 then
    return linebuffer
  end

  linebuffer:divider("─", "Comment")

  for _i, action in ipairs(actions) do
    linebuffer:newline()
    linebuffer:append("[", "CodeActionNormal")
    linebuffer:append(action.key, "CodeActionShortcut")
    linebuffer:append("] ", "CodeActionNormal")
    linebuffer:append(action.title, "CodeActionNormal")
    linebuffer:append(" (" .. action.action.kind .. ")", "Comment")
  end

  return linebuffer
end

function Diagnostics:goto_next_and_show(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local check_cursor = not self.popup

  local next_diagnostic =
    lsp2.get_next({ severity = severity, check_cursor = check_cursor })

  if next_diagnostic then
    vim.api.nvim_win_set_cursor(
      0,
      { next_diagnostic.lnum + 1, next_diagnostic.col }
    )
    self:show(next_diagnostic)
  else
    self:close()
  end
end

function Diagnostics:show(diagnostic)
  if self.popup then
    self:close()
  end

  local severity, highlight = utils.parse_severity(diagnostic.severity)

  local title_line = Line()
  title_line:append(Text(string.upper(severity), highlight))

  local code_actions = self:get_code_actions()
  self.main_buf = vim.api.nvim_get_current_buf()

  local linebuffer = make_diagnostic_lines(diagnostic, highlight, code_actions)

  self.popup = Popup({
    size = {
      width = linebuffer:width(),
      height = linebuffer:height(),
    },
    position = { row = 2, col = 1 },
    enter = false,
    focusable = true,
    zindex = 50,
    relative = "cursor",
    border = {
      padding = { top = 0, bottom = 0, left = 0, right = 0 },
      style = "rounded",
      text = {
        top = title_line,
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      -- winblend = 0,
      winhighlight = string.format(
        "Normal:%s,FloatBorder:%s",
        "Normal",
        highlight
      ),
    },
  })
  self.popup:mount()

  linebuffer:render(self.popup.bufnr)

  self:setup_autocmds()
  self:setup_keymaps(code_actions)
  -- Close popup when cursor leaves the window
  self.popup:on(event.BufLeave, function()
    self:close()
  end)
end

function Diagnostics:setup_autocmds()
  self.main_buf_autocmd_group =
    vim.api.nvim_create_augroup("MainBufAutoClose", { clear = true })
  local close_autocmds = { "CursorMoved", "InsertEnter" }
  vim.defer_fn(function()
    vim.api.nvim_create_autocmd(close_autocmds, {
      group = self.main_buf_autocmd_group,
      buffer = self.main_buf,
      once = true,
      callback = function(args)
        self:close()
        vim.api.nvim_del_autocmd(args.id)
      end,
    })
  end, 0)

  -- Close popup on various events
  self.main_buf_autocmd_group = vim.api.nvim_create_augroup(
    "PopupAutoClose" .. self.popup.bufnr,
    { clear = true }
  )
  self.autocmd_group = vim.api.nvim_create_augroup(
    "PopupAutoClose" .. self.popup.bufnr,
    { clear = true }
  )
  vim.api.nvim_create_autocmd(
    { "BufHidden", "InsertCharPre", "WinLeave", "FocusLost" },
    {
      group = self.autocmd_group,
      buffer = self.popup.bufnr,
      once = true,
      callback = function()
        self:close()
      end,
    }
  )
end

---@param options ActionOption[]
function Diagnostics:setup_keymaps(options)
  -- Set key mappings to dismiss the popup in the current window
  local current_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(current_win)
  for _, key in ipairs(self.opts.dismiss_keys) do
    vim.keymap.set({ "n", "v" }, key, function()
      self:close()
    end, {
      noremap = true,
      silent = true,
      buffer = bufnr,
    })
    table.insert(self.keymaps, {
      key = key,
      mode = { "n", "v" },
      buf = bufnr,
    })
  end

  for i, option in ipairs(options) do
    vim.keymap.set("n", option.key, function()
      lsp2.execute_command(option.action)
      self:close()
    end, {
      buffer = bufnr,
      noremap = true,
      silent = true,
      nowait = true,
    })
    table.insert(self.keymaps, {
      key = option.key,
      mode = { "n" },
      buf = bufnr,
    })
  end
end

function Diagnostics:close()
  -- Clean up keymaps
  for _, keymap in ipairs(self.keymaps) do
    vim.keymap.del(keymap.mode, keymap.key, { buffer = keymap.buf })
  end
  self.keymaps = {}

  -- Clean up autocommands
  if self.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, self.autocmd_group)
    self.autocmd_group = nil
  end

  if self.main_buf_autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, self.main_buf_autocmd_group)
    self.main_buf_autocmd_group = nil
  end

  if self.popup then
    self.popup:unmount()
    self.popup = nil
  end

  self.main_buf = nil
end

return Diagnostics
