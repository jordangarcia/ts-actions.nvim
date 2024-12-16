local logger = require("ts-actions.logger")
local utils = require("ts-actions.utils")
local api = vim.api
local lsp = vim.lsp

---@class LspClient
---@field pending_request boolean
local LspClient = {}
LspClient.__index = LspClient

---@param opts? {}
function LspClient:new(opts)
  ---@diagnostic disable-next-line: redefined-local
  local self = setmetatable({}, LspClient)
  self.pending_request = false
  return self
end

-- • {options}  (table|nil) Optional table which holds the following
--              optional fields:
--              • context: (table|nil) Corresponds to `CodeActionContext` of the LSP specification:
--                • diagnostics (table|nil): LSP `Diagnostic[]`. Inferred
--                  from the current position if not provided.
--                • only (table|nil): List of LSP `CodeActionKind`s used to
--                  filter the code actions. Most language servers support
--                  values like `refactor` or `quickfix`.
--                • triggerKind (number|nil): The reason why code actions
--                  were requested.
--
--              • filter: (function|nil) Predicate taking an `CodeAction`
--                and returning a boolean.
--              • apply: (boolean|nil) When set to `true`, and there is
--                just one remaining action (after filtering), the action
--                is applied without user query.
--              • range: (table|nil) Range for which code actions should be
--                requested. If in visual mode this defaults to the active
--                selection. Table must contain `start` and `end` keys with
--                {row, col} tuples using mark-like indexing. See
--                |api-indexing|

--
--
---@class CodeActionContext
---@field diagnostics? Diagnostic[]
---@field only? string[]
---@field triggerKind? number
--
---@class CodeActionOptions
---@field context? CodeActionContext
---@field apply? boolean
---@field range? { start: number, end: number }

---@param bufnr  number
---@param options CodeActionOptions
---@param callback fun(params: CodeActionResult[], options: CodeActionOptions): nil
function LspClient:request_code_actions(bufnr, options, callback)
  if self.pending_request then
    vim.notify("textDocument/codeAction request pending")
    return
  end

  options = options or {}
  options["context"] = options["context"] or {}

  if not options.context.triggerKind then
    options.context.triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked
  end

  if not options.context.diagnostics then
    local line, col = unpack(api.nvim_win_get_cursor(0))
    local line_diagnostics = lsp.diagnostic.get_line_diagnostics(
      api.nvim_get_current_buf(),
      line - 1,
      {},
      nil
    )

    logger:log("line_diagnostics", line_diagnostics)

    options.context.diagnostics = vim.tbl_filter(function(d)
      local is_multiline = d.range["end"].line
        and d.range["start"].line ~= d.range["end"].line

      local on_start_line = d.range["start"].line + 1 == line
      local on_end_line = d.range["end"].line + 1 == line

      logger:log("code actions diags", {
        line = line,
        col = col,
        is_multiline = is_multiline,
        on_start_line = on_start_line,
        on_end_line = on_end_line,
        d = d,
      })

      if
        not is_multiline
        and d.range["start"].character <= col
        and d.range["end"].character >= col
      then
        return true
      elseif
        is_multiline
        and on_start_line
        and d.range["start"].character <= col
      then
        return true
      elseif
        is_multiline
        and on_end_line
        and d.range["end"].character >= col
      then
        return true
      end

      return false
    end, line_diagnostics)
  end

  -- figure out the right range params to give to lsp client
  local mode = api.nvim_get_mode().mode
  local range = {}
  if options.range then
    assert(type(options.range) == "table", "code_action range must be a table")
    local start =
      assert(options.range.start, "range must have a `start` property")
    local end_ =
      assert(options.range["end"], "range must have a `end` property")
    range = lsp.util.make_given_range_params(start, end_)
  elseif mode == "v" or mode == "V" then
    local from_sel = utils.range_from_selection(0, mode)
    range = lsp.util.make_given_range_params(from_sel.start, from_sel["end"])
  else
    range = lsp.util.make_range_params()
  end

  -- build the final params
  -- lsp.util.make_range_params adds the textDocument field
  local final_params = vim.tbl_deep_extend("keep", options, range)

  logger:log("requesting code actions", final_params)
  self.pending_request = true

  -- TODO accum all here
  lsp.buf_request_all(
    bufnr,
    "textDocument/codeAction",
    final_params,
    function(results)
      self.pending_request = false
      ---@type CodeActionResult[]
      local actions = {}

      for client_id, item in pairs(results) do
        for _, action in ipairs(item.result or {}) do
          local client = vim.lsp.get_client_by_id(client_id)
          table.insert(actions, {
            action = action,
            client_id = client_id,
            client_name = client and client.name or "",
          })
        end
      end

      callback(actions, options)
    end
  )
end

---@param client any
---@param bufnr number
---@return boolean
function LspClient:supports_resolve(client, bufnr)
  if vim.version().minor >= 10 then
    local reg = client.dynamic_capabilities:get(
      "textDocument/codeAction",
      { bufnr = bufnr }
    )
    return vim.tbl_get(reg or {}, "registerOptions", "resolveProvider")
      or client.supports_method("codeAction/resolve")
  end
  return vim.tbl_get(
    client.server_capabilities,
    "codeActionProvider",
    "resolveProvider"
  )
end

---@param action CodeAction
---@param client any
---@param ctx { bufnr: integer, client_id: integer }
local function apply_action(action, client, ctx)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == "table" and action.command or action
    local func = client.commands[command.command]
      or vim.lsp.commands[command.command]
    if func then
      func(
        command,
        vim.tbl_deep_extend("force", {}, ctx, {
          client_id = client.id,
        })
      )
    else
      local params = {
        command = command.command,
        arguments = command.arguments,
        workDoneToken = command.workDoneToken,
      }
      client.request("workspace/executeCommand", params, nil, ctx.bufnr)
    end
  end
end

---@param action CodeAction
---@param ctx { bufnr: integer, client_id: integer }
function LspClient:apply_code_action(action, ctx)
  local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

  ---@type boolean
  local supports_resolve = false
  ---@diagnostic disable-next-line: undefined-field
  if action.data then
    supports_resolve = self:supports_resolve(client, ctx.bufnr)
  end

  if not action.edit and client and supports_resolve then
    client.request("codeAction/resolve", action, function(err, resolved_action)
      if err then
        if action.command then
          apply_action(action, client, ctx)
        else
          vim.notify(err.code .. ": " .. err.message, vim.log.levels.ERROR)
        end
      else
        apply_action(resolved_action, client, ctx)
      end
    end, ctx.bufnr)
  else
    apply_action(action, client, ctx)
  end
end

---get the line or cursor diagnostics
---@param opt table
---@return Diagnostic[]
local function get_diagnostic(opt)
  local cur_buf = vim.api.nvim_get_current_buf()
  local buf_diags = vim.diagnostic.get(cur_buf)
  if opt.buffer then
    return vim.diagnostic.get(cur_buf)
  end
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  local entrys = vim.diagnostic.get(cur_buf, { lnum = line - 1 })
  if opt.line then
    return entrys
  end

  if opt.cursor then
    local res = {}
    for _, v in pairs(buf_diags) do
      local is_multiline = v.end_lnum and v.lnum ~= v.end_lnum

      local in_line_range = v.lnum + 1 <= line and v.end_lnum + 1 >= line
      local on_start_line = v.lnum + 1 == line
      local on_end_line = v.end_lnum + 1 == line

      if not in_line_range then
        logger:log("not in line range")
      elseif
        not is_multiline
        and v.col <= col
        and v.end_col
        and v.end_col > col
      then
        res[#res + 1] = v
      elseif is_multiline and on_start_line and v.col <= col then
        res[#res + 1] = v
      elseif
        is_multiline and on_end_line and v.end_col and v.end_col > col or true
      then
        res[#res + 1] = v
      elseif is_multiline then
        res[#res + 1] = v
      end

      --
      -- if
      --   is_multiline
      --   and v.col <= col
      --   and v.lnum + 1 >= line
      --   and v.end_lnum + 1 <= line
      -- then
      --   res[#res + 1] = v
      -- elseif
      --   not is_multiline
      --   and v.col <= col
      --   and v.lnum + 1 >= line
      --   and v.end_lnum + 1 <= line
      --   and (v.end_col and v.end_col > col or true)
      -- then
      --   res[#res + 1] = v
      -- end
    end
    return res
  end
  return buf_diags
end

---@class GetNextOpts
---@field severity? DiagnosticSeverity
---@field pos 'next' | 'prev' | 'cursor'

---@class GotoDiagnosticOpts
---@field severity? DiagnosticSeverity

--
---@param opts? GetNextOpts
---@return Diagnostic|nil
function LspClient:get_diagnostic(opts)
  opts = opts or {}
  local severity = opts.severity or vim.diagnostic.severity.ERROR
  local pos = opts.pos or "next"

  if pos == "cursor" then
    local cursor_diagnostics = get_diagnostic({ cursor = true })
    if #cursor_diagnostics > 0 then
      -- Find the diagnostic with the highest severity (lowest severity number)
      local highest_severity_diag = cursor_diagnostics[1]
      for _, diag in ipairs(cursor_diagnostics) do
        if diag.severity < highest_severity_diag.severity then
          highest_severity_diag = diag
        end
      end
      return highest_severity_diag
    end
  end

  if pos == "prev" then
    return vim.diagnostic.get_prev({
      severity = { min = severity },
      wrap = true,
      float = false,
    })
  end

  return vim.diagnostic.get_next({
    severity = { min = severity },
    wrap = true,
    float = false,
  })
end

return LspClient
