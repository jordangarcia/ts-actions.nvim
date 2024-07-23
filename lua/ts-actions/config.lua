local logger = require("ts-actions.log")
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

---@param args Config
M.setup = function(args)
  logger:log("setup", M.config)
  if type(args.keys) == "string" then
    args.keys =
      vim.split(config.keys --[=[@as string]=], "", { trimempty = true })
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), args)
  if args.filter_function then
    M.config.filter_function = args.filter_function
  end
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "setup" then
      return M.setup
    end
    return rawget(M.config, key)
  end,
})
