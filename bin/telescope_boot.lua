-- Shared lazy.nvim + telescope bootstrap for standalone `nvim --clean -u
-- <tool>.lua` tools (pydef, fgr, ...). Each tool gets its own isolated cache
-- dir (stdpath('cache')/<cache_name>/lazy) so plugin installs never collide
-- and a fresh tool doesn't force a re-bootstrap of an existing one.
-- Usage: require('telescope_boot').setup{ cache_name = 'fgr-nvim', extra_plugin_specs = {...} }

local M = {}

function M.setup(opts)
  local cache_root = vim.fn.stdpath 'cache' .. '/' .. opts.cache_name
  local lazypath = cache_root .. '/lazy/lazy.nvim'
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local out = vim.fn.system {
      'git', 'clone', '--filter=blob:none', '--branch=stable',
      'https://github.com/folke/lazy.nvim.git', lazypath,
    }
    if vim.v.shell_error ~= 0 then
      error('Error cloning lazy.nvim:\n' .. out)
    end
  end
  vim.opt.rtp:prepend(lazypath)

  local specs = {
    {
      'nvim-telescope/telescope.nvim',
      dependencies = {
        'nvim-lua/plenary.nvim',
        { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
      },
    },
  }
  vim.list_extend(specs, opts.extra_plugin_specs or {})
  require('lazy').setup(specs, { root = cache_root .. '/lazy' })

  require('telescope').setup {
    defaults = {
      mappings = {
        i = {
          ['<C-j>'] = 'move_selection_next',
          ['<C-k>'] = 'move_selection_previous',
        },
        n = {
          ['<C-j>'] = 'move_selection_next',
          ['<C-k>'] = 'move_selection_previous',
        },
      },
    },
  }
  pcall(require('telescope').load_extension, 'fzf')

  return { cache_root = cache_root }
end

return M
