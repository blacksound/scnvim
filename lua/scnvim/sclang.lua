--- Spawn a sclang process.
-- @module scnvim/sclang
-- @author David Granström
-- @license GPLv3

local uv = vim.loop
local postwin = require('scnvim/postwin')
local udp = require('scnvim/udp')
local M = {}

--- Utilities

local cmd_char = {
  interpret_print = string.char(0x0c),
  interpret = string.char(0x1b),
  recompile = string.char(0x18),
}

local on_stdout = function()
  local stack = {''}
  return function(err, data)
    assert(not err, err)
    if data then
      table.insert(stack, data)
      local str = table.concat(stack, '')
      -- TODO: not sure if \r is needed.. need to check on windows.
      local got_line = vim.endswith(str, '\n') or vim.endswith(str, '\r')
      if got_line then
        local lines = vim.gsplit(str, '[\n\r]')
        for line in lines do
          if line ~= '' then
            postwin.print(line)
          end
        end
        stack = {''}
      end
    end
  end
end

local function safe_close(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

local function start_process()
  M.stdin = uv.new_pipe(false)
  M.stdout = uv.new_pipe(false)
  M.stderr = uv.new_pipe(false)

  local settings = vim.call('scnvim#util#get_user_settings')
  local sclang = settings.paths.sclang_executable
  local user_opts = vim.g.scnvim_sclang_options or {}
  assert(type(user_opts) == 'table', '[scnvim] g:scnvim_sclang_options must be an array')

  local options = {}
  options.stdio = {
    M.stdin,
    M.stdout,
    M.stderr,
  }
  options.cwd = vim.call('expand', '%:p:h')
  options.args = {'-i', 'scnvim', '-d', options.cwd}
  table.insert(options.args, user_opts)
  options.args = vim.tbl_flatten(options.args)
  -- windows specific settings
  options.verbatim = true
  options.hide = true

  return uv.spawn(sclang, options, vim.schedule_wrap(M.on_exit))
end

--- Interface

function M.send(data, silent)
  silent = silent or false
  if M.is_running() then
    M.stdin:write({
      data,
      not silent and cmd_char.interpret_print or cmd_char.interpret
    })
  end
end

function M.is_running()
  return M.proc and M.proc:is_active()
end

function M.eval(expr, cb)
  local cmd = string.format('SCNvim.eval("%s");', expr)
  udp.push_eval_callback(cb)
  M.send(cmd, true)
end

function M.on_exit()
  M.stdout:read_stop()
  M.stderr:read_stop()
  M.stdin:shutdown(function()
    safe_close(M.stdin)
  end)
  safe_close(M.stdout)
  safe_close(M.stderr)
  safe_close(M.proc)
  postwin.destroy()
  M.proc = nil
end

function M.recompile()
  if not M.is_running() then
    vim.call('scnvim#util#err', {'sclang is already running'})
    return
  end
  M.send(cmd_char.recompile, true)
  M.send(string.format('SCNvim.port = %d', udp.port), true)
  vim.call('scnvim#document#set_current_path')
end

function M.start()
  if M.is_running() then
    vim.call('scnvim#util#err', 'sclang is already running')
    return
  end
  postwin.create()
  M.proc = start_process()
  assert(M.proc, 'Could not open sclang process')
  local port = udp.start_server()
  assert(port > 0, 'Could not start UDP server')
  M.send(string.format('SCNvim.port = %d', port), true)
  vim.call('scnvim#document#set_current_path') -- TODO: should also move to lua
  local onread = on_stdout()
  M.stdout:read_start(vim.schedule_wrap(onread))
  M.stderr:read_start(vim.schedule_wrap(onread))
end

function M.stop()
  if not M.is_running() then
    return
  end
  udp.stop_server()
  M.send('0.exit', true)
  local timer = uv.new_timer()
  timer:start(1000, 500, function()
    if M.proc then
      local ret = M.proc:kill("SIGKILL")
      if ret == 0 then
        timer:close()
        M.proc = nil
      end
    else
      -- process exited during timer loop
      timer:close()
    end
  end)
end

return M
