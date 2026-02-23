local M = {}

local state = {
  buf_a = nil,
  buf_b = nil,
  win_a = nil,
  win_b = nil,
  buf_only_a = nil,
  buf_ab = nil,
  buf_only_b = nil,
  win_only_a = nil,
  win_ab = nil,
  win_only_b = nil,
  resize_autocmd = nil,
}

local function validate_diff_mode()
  local diff_bufs = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.wo[win].diff then
      local buf = vim.api.nvim_win_get_buf(win)
      table.insert(diff_bufs, {buf = buf, win = win})
    end
  end

  if #diff_bufs ~= 2 then
    vim.api.nvim_err_writeln("Error: Exactly 2 buffers with diffmode required")
    return false
  end

  state.buf_a = diff_bufs[1].buf
  state.buf_b = diff_bufs[2].buf
  state.win_a = diff_bufs[1].win
  state.win_b = diff_bufs[2].win
  return true
end

local function parse_diffopt()
  local diffopt = vim.o.diffopt
  local icase = diffopt:match("icase") ~= nil

  if diffopt:match("iwhiteall") then
    vim.notify("Warning: iwhiteall is not supported by :Comm", vim.log.levels.WARN)
  end

  return icase
end

local function build_sort_flags(icase)
  if icase then
    return "-u -f"
  else
    return "-u"
  end
end

local function build_preprocess_pipeline()
  return "sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\\+/ /g'"
end

local function run_comm(buf_a, buf_b, comm_flags)
  local lines_a = vim.api.nvim_buf_get_lines(buf_a, 0, -1, false)
  local lines_b = vim.api.nvim_buf_get_lines(buf_b, 0, -1, false)

  local tmp_a = os.tmpname()
  local tmp_b = os.tmpname()

  local file_a = io.open(tmp_a, "w")
  for _, line in ipairs(lines_a) do
    file_a:write(line .. "\n")
  end
  file_a:close()

  local file_b = io.open(tmp_b, "w")
  for _, line in ipairs(lines_b) do
    file_b:write(line .. "\n")
  end
  file_b:close()

  local icase = parse_diffopt()
  local sort_flags = build_sort_flags(icase)
  local preprocess = build_preprocess_pipeline()

  local cmd = string.format(
    "comm %s <(cat %s | %s | sort %s) <(cat %s | %s | sort %s)",
    comm_flags, tmp_a, preprocess, sort_flags, tmp_b, preprocess, sort_flags
  )

  local handle = io.popen("bash -c " .. vim.fn.shellescape(cmd))
  local result = handle:read("*a")
  handle:close()

  os.remove(tmp_a)
  os.remove(tmp_b)

  local output = {}
  for line in result:gmatch("[^\n]*") do
    if line ~= "" then
      table.insert(output, line)
    end
  end

  return output
end

local function find_or_create_buffer(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == name or buf_name:match(name .. "$") then
        return buf
      end
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.api.nvim_buf_set_name(buf, name)
  return buf
end

local function create_output_layout()
  -- Get basenames of A and B buffers
  local name_a = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(state.buf_a), ":t")
  local name_b = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(state.buf_b), ":t")

  -- Create buffer names with source file basenames
  local buf_name_only_a = "ONLY-" .. name_a
  local buf_name_ab = "BOTH-" .. name_a .. "+" .. name_b
  local buf_name_only_b = "ONLY-" .. name_b

  -- Delete old output buffers if they exist with different names
  if state.buf_only_a and vim.api.nvim_buf_is_valid(state.buf_only_a) then
    local old_name = vim.api.nvim_buf_get_name(state.buf_only_a)
    if old_name ~= buf_name_only_a and old_name ~= "" then
      vim.api.nvim_buf_delete(state.buf_only_a, {force = true})
      state.buf_only_a = nil
    end
  end
  if state.buf_ab and vim.api.nvim_buf_is_valid(state.buf_ab) then
    local old_name = vim.api.nvim_buf_get_name(state.buf_ab)
    if old_name ~= buf_name_ab and old_name ~= "" then
      vim.api.nvim_buf_delete(state.buf_ab, {force = true})
      state.buf_ab = nil
    end
  end
  if state.buf_only_b and vim.api.nvim_buf_is_valid(state.buf_only_b) then
    local old_name = vim.api.nvim_buf_get_name(state.buf_only_b)
    if old_name ~= buf_name_only_b and old_name ~= "" then
      vim.api.nvim_buf_delete(state.buf_only_b, {force = true})
      state.buf_only_b = nil
    end
  end

  state.buf_only_a = find_or_create_buffer(buf_name_only_a)
  state.buf_ab = find_or_create_buffer(buf_name_ab)
  state.buf_only_b = find_or_create_buffer(buf_name_only_b)

  -- Check if windows already exist
  local need_create_windows = not (state.win_only_a and vim.api.nvim_win_is_valid(state.win_only_a))

  if need_create_windows then
    -- Create a new window at the very bottom spanning full width
    vim.api.nvim_set_current_win(state.win_a)
    vim.cmd("botright split")

    -- botright split creates the first window (this will be rightmost after splits)
    local win_for_only_b = vim.api.nvim_get_current_win()

    -- Split vertically - new window appears on the right (this will be middle)
    vim.cmd("vsplit")
    local win_for_ab = vim.api.nvim_get_current_win()

    -- Split vertically again - new window appears on the right (this will be leftmost visually)
    vim.cmd("vsplit")
    local win_for_only_a = vim.api.nvim_get_current_win()

    -- Assign windows to state
    state.win_only_a = win_for_only_a
    state.win_ab = win_for_ab
    state.win_only_b = win_for_only_b

    vim.api.nvim_win_set_buf(state.win_only_a, state.buf_only_a)
    vim.api.nvim_win_set_buf(state.win_ab, state.buf_ab)
    vim.api.nvim_win_set_buf(state.win_only_b, state.buf_only_b)

    vim.wo[state.win_only_a].diff = false
    vim.wo[state.win_ab].diff = false
    vim.wo[state.win_only_b].diff = false
  end
end

local function resize_windows()
  if not (state.win_a and state.win_b and state.win_only_a and state.win_ab and state.win_only_b) then
    return
  end

  if not (vim.api.nvim_win_is_valid(state.win_a) and vim.api.nvim_win_is_valid(state.win_b) and
          vim.api.nvim_win_is_valid(state.win_only_a) and vim.api.nvim_win_is_valid(state.win_ab) and
          vim.api.nvim_win_is_valid(state.win_only_b)) then
    return
  end

  -- Get current window to restore later
  local current = vim.api.nvim_get_current_win()

  local total_width = vim.o.columns
  local total_height = vim.o.lines - vim.o.cmdheight - 1

  -- Set heights: top 50%, bottom 50%
  local half_height = math.floor(total_height / 2)
  vim.api.nvim_set_current_win(state.win_a)
  vim.api.nvim_win_set_height(state.win_a, half_height)

  -- Set top widths: A and B at 50% each
  local half_width = math.floor(total_width / 2)
  vim.api.nvim_win_set_width(state.win_a, half_width)

  -- Set bottom widths: each at 33%
  local third_width = math.floor(total_width / 3)
  vim.api.nvim_set_current_win(state.win_only_a)
  vim.api.nvim_win_set_width(state.win_only_a, third_width)

  vim.api.nvim_set_current_win(state.win_ab)
  vim.api.nvim_win_set_width(state.win_ab, third_width)

  vim.api.nvim_set_current_win(state.win_only_b)
  vim.api.nvim_win_set_width(state.win_only_b, third_width)

  -- Restore original window
  if vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
end

local function populate_buffers()
  local only_a = run_comm(state.buf_a, state.buf_b, "-23")
  local ab = run_comm(state.buf_a, state.buf_b, "-12")
  local only_b = run_comm(state.buf_a, state.buf_b, "-13")

  vim.bo[state.buf_only_a].modifiable = true
  vim.bo[state.buf_only_a].readonly = false
  vim.bo[state.buf_ab].modifiable = true
  vim.bo[state.buf_ab].readonly = false
  vim.bo[state.buf_only_b].modifiable = true
  vim.bo[state.buf_only_b].readonly = false

  vim.api.nvim_buf_set_lines(state.buf_only_a, 0, -1, false, only_a)
  vim.api.nvim_buf_set_lines(state.buf_ab, 0, -1, false, ab)
  vim.api.nvim_buf_set_lines(state.buf_only_b, 0, -1, false, only_b)

  vim.bo[state.buf_only_a].readonly = true
  vim.bo[state.buf_only_a].modifiable = false
  vim.bo[state.buf_ab].readonly = true
  vim.bo[state.buf_ab].modifiable = false
  vim.bo[state.buf_only_b].readonly = true
  vim.bo[state.buf_only_b].modifiable = false
end

local function setup_resize_autocmd()
  if state.resize_autocmd then
    vim.api.nvim_del_autocmd(state.resize_autocmd)
  end

  state.resize_autocmd = vim.api.nvim_create_autocmd("VimResized", {
    callback = resize_windows,
  })
end

function M.comm()
  if not validate_diff_mode() then
    return
  end

  create_output_layout()
  populate_buffers()
  resize_windows()
  setup_resize_autocmd()
end

vim.api.nvim_create_user_command("Comm", M.comm, {})

return M
