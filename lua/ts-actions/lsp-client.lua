local logger = require("ts-actions.log")
local utils = require("ts-actions.utils")
local api = vim.api
local lsp = vim.lsp

---@class LspClient
---@field pending_request boolean
local LspClient = {}
LspClient.__index = LspClient

---@param opts? {}
function LspClient:new(opts)
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
    vim.notify("Cannot request_code_actions, request pending")
    return
  end

  options = options or {}
  options["context"] = options["context"] or {}

  if not options.context.diagnostics then
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    options.context.diagnostics = lsp.diagnostic.get_line_diagnostics(
      api.nvim_get_current_buf(),
      lnum,
      {},
      nil
    )
    logger:log("got diag", options.context.diagnostics)
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

  self.pending_request = true

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

return LspClient
