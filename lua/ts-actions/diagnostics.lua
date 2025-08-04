---@type ParsedConfig
local config = require("ts-actions.config")
local logger = require("ts-actions.logger")

local Line = require("nui.line")
local LineBuffer = require("ts-actions.line-buffer")
local LspClient = require("ts-actions.lsp-client")
local Popup = require("nui.popup")
local Text = require("nui.text")
local keys = require("ts-actions.keys")
local utils = require("ts-actions.utils")

---@class Diagnostics
---@field popup any
---@field client LspClient
---@field keymaps {key: string, mode: string[], buf: number}[]
---@field main_buf number|nil
---@field autocmd_group number|nil
local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics:new()
  local self = setmetatable({}, Diagnostics)
  self.client = LspClient:new()
  self.popup = nil
  self.keymaps = {}
  self.autocmd_group = nil
  self.main_buf = nil
  return self
end

---@param diagnostics vim.Diagnostic[]
---@param callback fun(actions: ActionOption[]): nil
function Diagnostics:get_code_actions(diagnostics, callback)
  local bufnr = vim.api.nvim_get_current_buf()

  self.client:request_code_actions(
    bufnr,
    vim.lsp.diagnostic.from(diagnostics),
    function(code_actions)
      local used_keys = {}
      ---@type ActionOption[]
      local options = {}

      for i, result in ipairs(code_actions) do
        local action = result.action
        if action.title then
          local match = keys.get_action_config({
            title = action.title,
            priorities = config.priority[vim.bo.filetype],
            valid_keys = config.keys,
            invalid_keys = used_keys,
            override_function = function(_) end,
          })

          if match then
            options[i] = {
              action = action,
              client_id = result.client_id,
              title = action.title,
              order = match.order,
              key = match.key,
            }
          else
            logger:log("Unable to find key for action: " .. action.title)
          end
        end
      end

      options = utils.priority_sort(options)
      -- logger:log(
      --   "actions (unfiltered)",
      --   vim.tbl_map(function(entry)
      --     return {
      --       title = entry.title,
      --       key = entry.key,
      --       kind = entry.action.kind,
      --     }
      --   end, options)
      -- )

      if config.filter_function then
        options = vim.tbl_filter(function(option)
          return config.filter_function(option.action)
        end, options)
      end

      callback(options)
    end
  )
end

---@param diagnostic Diagnostic
---@param highlight string
---@param actions? ActionOption[]
---@return LineBuffer
local function make_diagnostic_lines(diagnostic, highlight, actions)
  local linebuffer = LineBuffer:new({ max_width = 80, padding = 1 })

  linebuffer:append(diagnostic.message, highlight)
  local diagnostic_str = utils.diagnostic_source_str(diagnostic)
  -- Add source and code if available
  if diagnostic_str then
    linebuffer:append(" " .. diagnostic_str, "Comment")
  end

  if not actions or #actions == 0 then
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

function Diagnostics:goto_prev_and_show(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local check_cursor = not self.popup

  local next_diagnostic = self.client:get_diagnostic({
    severity = severity,
    pos = check_cursor and "cursor" or "prev",
  })

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

function Diagnostics:goto_next_and_show(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR

  local incursor = self.client:get_diagnostic({
    severity = severity,
    pos = "cursor",
  })
  local entry

  if incursor and not self.popup then
    logger:log("incursor and not popup", incursor)
    entry = incursor
  else
    logger:log("going to next", incursor)
    entry = self.client:get_diagnostic({
      severity = severity,
      pos = "next",
    })
  end

  if entry then
    vim.api.nvim_win_set_cursor(0, { entry.lnum + 1, entry.col })
    self:show(entry)
  elseif self.popup then
    self:close()
  end
  -- if not next_diagnostic then
  --   self:close()
  --   return
  -- end
  --
  -- vim.api.nvim_win_set_cursor(
  --   0,
  --   { next_diagnostic.lnum + 1, next_diagnostic.col }
  -- )
  -- self:show(next_diagnostic)
end

function Diagnostics:show(diagnostic)
  if self.popup then
    self:close()
  end

  local severity, highlight = utils.parse_severity(diagnostic.severity)

  local title_line = Line()
  title_line:append(Text(string.upper(severity), highlight))

  self.main_buf = vim.api.nvim_get_current_buf()

  local linebuffer = make_diagnostic_lines(diagnostic, highlight)
  local anchor, position, size = self:compute_position(linebuffer)

  self.popup = Popup({
    anchor = anchor,
    position = position,
    size = size,
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
  self:setup_dismiss_keys()

  -- request code actions
  self:get_code_actions({ diagnostic }, function(actions)
    if not self.popup then
      -- dont render if the popup has been closed
      return
    end

    -- re-render the modal
    local new_buffer = make_diagnostic_lines(diagnostic, highlight, actions)
    new_buffer:render(self.popup.bufnr)

    local anchor, position, size = self:compute_position(new_buffer)
    self.popup:update_layout({
      anchor = anchor,
      position = position,
      size = size,
    })

    self:setup_code_action_keys(actions)
  end)
end

---@param linebuffer LineBuffer
function Diagnostics:compute_position(linebuffer)
  local width = linebuffer:width()
  local height = linebuffer:height()

  -- get the cursor position from the bottom of the window
  local winline = vim.fn.winline()
  local winheight = vim.api.nvim_win_get_height(0)

  local space_below = winheight - winline

  local buffer = 5 + 2 -- for padding
  local position = { row = 2, col = 1 }
  local anchor = "NW"
  if space_below < height + buffer then
    anchor = "SW"
    position = { row = 1, col = 1 }
  end
  local size = {
    width = width,
    height = height,
  }

  return anchor, position, size
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
  self.autocmd_group = vim.api.nvim_create_augroup(
    "PopupAutoClose" .. self.popup.bufnr,
    { clear = true }
  )

  -- this is separate becuase it needs to be listened
  -- to on another buffer
  vim.api.nvim_create_autocmd({ "WinLeave" }, {
    group = self.autocmd_group,
    once = true,
    callback = function()
      self:close()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufHidden", "InsertCharPre", "FocusLost" }, {
    group = self.autocmd_group,
    buffer = self.popup.bufnr,
    once = true,
    callback = function()
      self:close()
    end,
  })
end

function Diagnostics:setup_dismiss_keys()
  -- Set key mappings to dismiss the popup in the current window
  local current_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(current_win)
  for _, key in ipairs(config.dismiss_keys) do
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
end

---@param options ActionOption[]
function Diagnostics:setup_code_action_keys(options)
  local current_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(current_win)

  for i, option in ipairs(options) do
    vim.keymap.set("n", option.key, function()
      self.client:apply_code_action(option.action, {
        bufnr = self.main_buf,
        client_id = option.client_id,
      })
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
    -- NOTE: this is a workaround for a keymap being introduced that isn't actually bound
    -- when calling self:get_code_actions(), introduced when we filter out the actions
    pcall(vim.keymap.del, keymap.mode, keymap.key, { buffer = keymap.buf })
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
