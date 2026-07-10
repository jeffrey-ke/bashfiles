-- Standalone, self-bootstrapping nvim config for interactive live-grep
-- search (rg content + live glob/fuzzy refinement), a pydef-sibling tool.
-- Invoked via `nvim --clean -u fgr.lua`.
-- Usage: nvim --clean -u fgr.lua -c "FGrep [prompt] [dir]"

-- debug.getinfo source is this file's absolute path (the launcher passes -u
-- via readlink -f), so this resolves regardless of cwd; bin/ isn't on
-- package.path by default.
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
package.path = script_dir .. '/?.lua;' .. package.path
require('telescope_boot').setup {
  cache_name = 'fgr-nvim',
  extra_plugin_specs = { 'nvim-telescope/telescope-live-grep-args.nvim' },
}

-- telescope-live-grep-args's own `actions` module (checked against the
-- installed source post-bootstrap) only re-exports quote_prompt, not
-- to_fuzzy_refine despite the README showing `lga_actions.to_fuzzy_refine` —
-- that one lives on telescope core's actions table.
local core_actions = require 'telescope.actions'
local lga_actions = require 'telescope-live-grep-args.actions'

-- <C-i> is indistinguishable from <Tab> in terminals (same keycode), and
-- <Tab> is telescope's default multi-select toggle — binding <C-i> here
-- would silently shadow it. Use <M-i> instead.
local lga_mappings = {
  ['<C-Space>'] = core_actions.to_fuzzy_refine,
  ['<M-i>'] = lga_actions.quote_prompt { postfix = ' --iglob ' },
}
require('telescope').setup {
  extensions = {
    live_grep_args = {
      mappings = { i = lga_mappings, n = lga_mappings },
    },
  },
}
require('telescope').load_extension 'live_grep_args'

local function fuzzy_grep_picker(opts)
  opts = opts or {}
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or (vim.uv or vim.loop).cwd()
  opts.additional_args = function(o)
    local args = { '--hidden', '--glob=!**/.git/**' }
    -- alldocs/ is a symlink farm (see CLAUDE.md); rg won't follow symlinked
    -- dirs by default, which would silently return zero results under it.
    if vim.fn.fnamemodify(o.cwd, ':p'):find('/alldocs', 1, true) then
      table.insert(args, '--follow')
    end
    return args
  end
  require('telescope').extensions.live_grep_args.live_grep_args(opts)
end

vim.api.nvim_create_user_command('FGrep', function(cmd_opts)
  local args = vim.split(cmd_opts.args, '%s+')
  -- Same startup-focus race as pydef.lua's :PyDef — see its comment.
  vim.schedule(function()
    fuzzy_grep_picker {
      -- live-grep-args only splits later-typed flags (e.g. `--iglob !*.md`)
      -- out of the pattern when the CURRENT full prompt string starts with
      -- a quote char (its own auto_quoting rule, prompt_parser.lua); quote
      -- the seeded term so appending flags works immediately, matching its
      -- own README usage (`"foo" --iglob ...`).
      default_text = args[1] ~= '' and ('"' .. args[1] .. '"') or nil,
      cwd = args[2],
    }
  end)
end, { nargs = '*' })

-- <C-q> (telescope default) sends results to the quickfix list and closes
-- the picker; this resumes it afterwards from anywhere in the instance.
vim.keymap.set('n', '<C-f>', function()
  require('telescope.builtin').resume()
end, { desc = 'Resume last Telescope picker' })
