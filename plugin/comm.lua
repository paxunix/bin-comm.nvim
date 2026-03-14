if vim.g.loaded_comm_plugin == 1 then
  return
end

vim.g.loaded_comm_plugin = 1

vim.api.nvim_create_user_command("Comm", function()
  require("comm").comm()
end, {})
