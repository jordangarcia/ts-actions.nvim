local event = require("nui.utils.autocmd").event
local NuiLine = require("nui.line")
local NuiPopup = require("nui.popup")
local NuiText = require("nui.text")

local Popup = {}
Popup.__index = Popup

local style_configs = {
  error = {
    title = "Error",
    highlight = "DiagnosticError",
  },
  warn = {
    title = "Warning",
    highlight = "DiagnosticWarn",
  },
  hint = {
    title = "Hint",
    highlight = "DiagnosticHint",
  },
  info = {
    title = "Info",
    highlight = "DiagnosticInfo",
  },
}

function Popup.new(options)
  local self = setmetatable({}, Popup)
  self.options = vim.tbl_deep_extend("force", {
    content = {},
    title = nil,
    size = { width = 50, height = 10 },
    position = { row = 2, col = 1 },
    dismiss_keys = { "j", "k", "<C-c>", "q" },
    relative = "cursor",
    style = "hint", -- default style
  }, options or {})

  local style_config = style_configs[self.options.style] or style_configs.hint

  -- Create a NuiText object for the title with the appropriate highlight
  local title = self.options.title or style_config.title
  local highlighted_title = NuiText(title, style_config.highlight)
  self.popup = NuiPopup({
    size = self.options.size,
    position = self.options.position,
    enter = false,
    focusable = true,
    zindex = 50,
    relative = self.options.relative,
    border = {
      padding = { top = 0, bottom = 0, left = 1, right = 1 },
      style = "rounded",
      text = {
        top = highlighted_title,
        top_align = "center",
      },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      winhighlight = string.format("Normal:%s,FloatBorder:%s", style_config.highlight, style_config.highlight),
    },
  })
  self.keymaps = {}
  return self
end

function Popup:mount()
  self.popup:mount()

  -- Set content
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, self.options.content)
  -- Set key mappings to dismiss the popup in the current window
  local current_win = vim.api.nvim_get_current_win()
  for _, key in ipairs(self.options.dismiss_keys) do
    local keymap = vim.keymap.set({ "n", "v" }, key, function()
      self:close()
    end, { noremap = true, silent = true, buffer = vim.api.nvim_win_get_buf(current_win) })
    table.insert(self.keymaps, { key = key, mode = { "n", "v" }, buf = vim.api.nvim_win_get_buf(current_win) })
  end
  -- Close popup when cursor leaves the window
  self.popup:on(event.BufLeave, function()
    self:close()
  end)
  -- Close popup on various events
  self.autocmd_group = vim.api.nvim_create_augroup("PopupAutoClose" .. self.popup.bufnr, { clear = true })
  vim.api.nvim_create_autocmd({ "BufHidden", "InsertCharPre", "WinLeave", "FocusLost" }, {
    group = self.autocmd_group,
    buffer = self.popup.bufnr,
    once = true,
    callback = function()
      self:close()
    end,
  })
end

function Popup:close()
  -- Clean up keymaps
  for _, keymap in ipairs(self.keymaps) do
    vim.keymap.del(keymap.mode, keymap.key, { buffer = keymap.buf })
  end
  self.keymaps = {}
  -- Clean up autocommands
  if self.autocmd_group then
    vim.api.nvim_del_augroup_by_id(self.autocmd_group)
    self.autocmd_group = nil
  end
  -- Unmount the popup
  self.popup:unmount()
end

function Popup:update_content(new_content)
  vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, new_content)
end

function Popup:write_lines(lines)
  if not self.popup or not self.popup.bufnr then
    return
  end

  -- Clear existing content
  -- vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, {})

  -- Write each NuiLine to the buffer
  for i, line in ipairs(lines) do
    line:render(self.popup.bufnr, -1, i)
  end
end

local M = {}

function M.create_popup(options)
  return Popup.new(options)
end

return M
