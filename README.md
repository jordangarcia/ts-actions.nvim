# `ts-actions.nvim`


- **Popup Interface**: Display code actions in a customizable popup window.
- **Keybindings**: Configure keys to quickly dismiss or select code actions,
  making your workflow more efficient.
- **Priority Handling**: Customize the display order of actions based on
  priority, ensuring the most used actions are always visible on top.

## Installation + Example Config

Using `lazy.nvim`

```lua
local ts_priority_f = {
  { key = "f", pattern = "^update import", order = 102 },
  { key = "f", pattern = "^add import", order = 101 },
  { key = "f", pattern = "^fix this", order = 101 },
  { key = "f", pattern = "^add async modifier", order = 100 },
  { key = "f", pattern = "^change spelling", order = 100 },
  { key = "f", pattern = "^remove unused", order = 100 },
  { key = "f", pattern = "^prefix .* with an underscore", order = 100 },
  { key = "f", pattern = "^update the dependencies array", order = 100 },
  { key = "F", pattern = "^fix all", order = 99 },
  { key = "d", pattern = "disable .* for this line", order = 99 },
  { key = "D", pattern = "disable .* entire file", order = 98 },
}

---@type LazyPluginSpec[]
return {
  {
    "jordangarcia/ts-actions.nvim",
    event = "VeryLazy",
    keys = {
      {
        "<C-S-n>",
        function()
          require("ts-actions").prev()
        end,
        desc = "[p]rev",
        mode = "n",
      },
      {
        "<C-n>",
        function()
          require("ts-actions").next()
        end,
        desc = "[n]ext",
        mode = "n",
      },
    },
    dependencies = {
      { "MunifTanjim/nui.nvim", lazy = true },
    },

    config = function()
      require("ts-actions").setup {
        ---@type table<string, { pattern: string, key: string, order?: integer }[]>
        priority = {
          ["typescript"] = ts_priority_f,
          ["typescriptreact"] = ts_priority_f,
        },
        severity = {
          ["typescriptreact"] = vim.diagnostic.severity.ERROR,
          ["typescript"] = vim.diagnostic.severity.ERROR,
          ["lua"] = vim.diagnostic.severity.WARN,
        },
        ---@param action LocalCodeAction
        filter_function = function(action)
          -- Check if title exists and contains "refactor."
          if type(action.kind) == "string" and action.kind:find "^refactor%." then
            return false
          end

          if action.title:match "missing function declaration" then
            return false
          end
          -- Default to false if none of the conditions are met
          return true
        end,
      }
    end,
  },
}
```
