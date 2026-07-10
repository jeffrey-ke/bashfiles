-- Standalone, self-bootstrapping nvim config for interactive Python
-- def/class search. Independent of any user nvim config — invoked via
-- `nvim --clean -u pydef.lua`. Installs its own minimal plugin set into a
-- dedicated cache dir on first run (like a `uv run --with` ephemeral env),
-- reused on subsequent runs.
-- Usage: nvim --clean -u pydef.lua -c "PyDef [name] [dir]"

-- debug.getinfo source is this file's absolute path (the launcher passes -u
-- via readlink -f), so this resolves regardless of cwd; bin/ isn't on
-- package.path by default.
local script_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
package.path = script_dir .. '/?.lua;' .. package.path
require('telescope_boot').setup { cache_name = 'pydef-nvim' }

local function python_def_picker(opts)
  opts = opts or {}
  opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.uv.cwd()

  local conf = require('telescope.config').values
  local make_entry = require 'telescope.make_entry'
  opts.entry_maker = opts.entry_maker or make_entry.gen_from_vimgrep(opts)

  -- Requires actual definition syntax, not just the bare words "def"/"class"
  -- appearing anywhere in a line: anchored to line-start (after indentation,
  -- optional "async "), and the keyword must be followed by a real
  -- identifier then immediately "(", ":", or "[" (generic class). A bare
  -- `(def|class)\s+` substring search also matches those words as plain
  -- English inside docstrings/comments (e.g. a docstring line describing
  -- something "in CLASS space") — this shape only matches real syntax.
  -- --case-sensitive overrides the inherited --smart-case, since real
  -- keywords are always lowercase.
  local args = vim.list_extend(vim.deepcopy(conf.vimgrep_arguments), {
    '--glob=*.py',
    '--case-sensitive',
    '--',
    '^\\s*(async\\s+)?(def|class)\\s+\\w+\\s*[:\\(\\[]',
  })

  require('telescope.pickers').new(opts, {
    prompt_title = 'Python Definitions',
    finder = require('telescope.finders').new_oneshot_job(args, opts),
    previewer = conf.grep_previewer(opts),
    sorter = conf.generic_sorter(opts),
  }):find()
end

vim.api.nvim_create_user_command('PyDef', function(cmd_opts)
  local args = vim.split(cmd_opts.args, '%s+')
  -- Deferred: opening the picker synchronously from a `-c` startup command
  -- races Neovim's own initial-window setup and leaves keyboard focus on the
  -- preview window instead of the prompt (reproduces identically with plain
  -- `nvim -c "lua require('telescope.builtin').live_grep()"` against a
  -- normal config, so it's a generic startup-timing quirk, not specific to
  -- this picker). vim.schedule defers to the next event loop tick, after
  -- startup has settled, which fixes it.
  vim.schedule(function()
    python_def_picker {
      default_text = args[1] ~= '' and args[1] or nil,
      cwd = args[2],
    }
  end)
end, { nargs = '*' })
