---@type ParsedConfig
local default_config = {
  dismiss_keys = { "<esc>", "<c-c>", "q" },
  keys = vim.split(
    "wertyuiopasdfghlzxcvbnm" --[=[@as string]=],
    "",
    { trimempty = true }
  ),
  override_function = function(_) end,
  priority = {},
  severity = {},
  log_level = "info",
}

local M = {
  ---@type ParsedConfig
  config = vim.deepcopy(default_config),
}

M.setup = function(args)
  if type(args.keys) == "string" then
    args.keys =
      vim.split(config.keys --[=[@as string]=], "", { trimempty = true })
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), args)
end

return M
