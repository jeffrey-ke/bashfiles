set number relativenumber
set tabstop=4       " Number of spaces that a <Tab> in the file counts for
set softtabstop=4
set shiftwidth=4    " Number of spaces to use for each step of autoindent
set softtabstop=4
set expandtab       " Convert tabs to spaces
" keymaps
nnoremap <Space>h <C-w>h
nnoremap <Space>l <C-w>l
nnoremap <Space>j <C-w>j
nnoremap <Space>k <C-w>k
nnoremap <silent> <Space>u :call smooth_scroll#up(&scroll, 15, 1)<CR>
nnoremap <silent> <Space>d :call smooth_scroll#down(&scroll, 15, 1)<CR>
tnoremap <Esc><Esc> <C-\><C-n>
nnoremap <Space>b :NERDTreeToggle<CR>
nnoremap <Space>t :call ToggleTerminal()<CR>
nnoremap <Space><Space> za
inoremap <Tab> <C-R>=Tab_Or_Complete()<CR>
nnoremap ff :call FoldExceptCursor()<CR>
nnoremap <Space>p '[V']
nnoremap $ ^
nnoremap ^ $
vnoremap $ ^
vnoremap ^ $
onoremap $ ^
onoremap ^ $


command! AT ALEToggle
set mouse=a
" This setting makes search case-insensitive when all characters in the string
" being searched are lowercase. However, the search becomes case-sensitive if
" it contains any capital letters. This makes searching more convenient.
set ignorecase
set smartcase
" For status lines
set laststatus=2

" Enable searching as you type, rather than waiting till you press enter.
set incsearch

" code folding
set foldmethod=indent
set foldnestmax=6
" words now wrap.
set linebreak
" hard line-length limit: typing past column 80 wraps to the next line
set textwidth=80
" 't' auto-wraps plain text, 'c' auto-wraps comments, at 'textwidth'.
" Re-applied per buffer because ftplugins (python, gitcommit, ...) reset both.
set formatoptions+=tc
augroup TextWidth
    autocmd!
    autocmd FileType * setlocal textwidth=80 formatoptions+=tc
augroup END

" ── spell checking ──────────────────────────────────────────────────────────
" 'en_us' is a *region* inside the bundled en.utf-8.spl (vim 9.1 and nvim both
" ship it), so nothing is ever downloaded. British spellings are then flagged
" as 'rare' (SpellRare) rather than wrong.
set spelllang=en_us
" Words added with zg go in the repo so they travel between machines; vim's
" default (~/.vim/spell/, or the nvim config dir) is not version-controlled.
set spellfile=~/dotfiles/spell/en.utf-8.add
" Check camelCase/snake_case parts separately instead of reading an identifier
" as one long typo. silent! because older vim lacks the 'camel' value.
silent! set spelloptions+=camel
" vim only reads the compiled .add.spl beside the list, and spell/.gitignore
" excludes *.spl as a binary artifact. zg recompiles on add, but a fresh clone has
" no .add.spl and a pull from another machine leaves the old one stale -- either
" way every tracked word reads as a typo. getftime() is -1 when the file is
" missing, so one comparison covers both cases.
let s:spell_add = expand('~/dotfiles/spell/en.utf-8.add')
if filereadable(s:spell_add) && getftime(s:spell_add) > getftime(s:spell_add . '.spl')
  silent! execute 'mkspell! ' . fnameescape(s:spell_add)
endif
" Prose filetypes only — a global 'spell' underlines every identifier in code.
augroup Spell
    autocmd!
    autocmd FileType tex,plaintex,markdown,text,gitcommit,rst setlocal spell
    " Journal entries are named by date (~/journal/aug18) with no extension, so
    " vim gives them no filetype and the FileType rule above never fires; match
    " on path instead (autocmd patterns expand '~'). The second 'spellfile'
    " entry lets 2zg file a word with the journal (names, jargon) while plain zg
    " still writes to the dotfiles list. Words in both files count as good; the
    " count only picks which file gets written.
    autocmd BufRead,BufNewFile ~/journal/* setlocal spell spellfile+=~/journal/.spell.add
augroup END
" For a one-off prose buffer vim didn't recognize: toggle spell on this buffer.
" ('1z=' in the mapping below errors with E756 when 'spell' is off.)
nnoremap <Space>s :setlocal spell!<CR>:setlocal spell?<CR>
" ── yank -> system clipboard ─────────────────────────────────────────────────
" Mirror every *yank* into the macOS pasteboard, so y is enough and cmd-c is
" not needed to hand text to another app. Deliberately not 'clipboard=unnamed':
" that routes deletes through the pasteboard too, so a stray x or dd would
" clobber what you copied. TextYankPost fires for d/c/y alike, hence the
" operator check; regcontents+regtype keep linewise and blockwise yanks intact.
" macOS-only: on the Linux hosts this file is shared with, writing '*' means an
" X11 connection that an ssh session usually does not have.
if has('mac') && has('clipboard') && exists('##TextYankPost')
  augroup YankToClipboard
    autocmd!
    autocmd TextYankPost *
          \ if v:event.operator ==# 'y' |
          \   call setreg('*', v:event.regcontents, v:event.regtype) |
          \ endif
  augroup END
endif
" Fix the previous typo without leaving insert mode (castel.dev/post/lecture-notes-1):
" [s jumps back to it, 1z= takes the first suggestion, `]a returns to where you
" were typing. The <c-g>u breaks make the whole correction a single undo.
inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u
" terminal keymap timeout
set ttimeoutlen=50
" ???
let g:netrw_liststyle=3
" installing plugins
call plug#begin()
Plug 'ryanoasis/vim-devicons'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'dense-analysis/ale'
Plug 'tpope/vim-commentary'
Plug 'preservim/nerdtree'
Plug 'tpope/vim-fugitive'
Plug 'vim-airline/vim-airline'
Plug 'sainnhe/everforest'
Plug 'ghifarit53/tokyonight-vim'
Plug 'terryma/vim-smooth-scroll'
Plug 'heavenshell/vim-pydocstring', { 'do': 'make install', 'for': 'python' }
call plug#end()
" color scheme
filetype plugin indent on
" ctrlp options
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
let g:ctrlp_working_path_mode = 'ra'

" fonts
set encoding=utf8
set guifont=AurulentSansMNerdFontMono-Regular\ Nerd\ Font\ 11
" nerdtree config
let NERDTreeShowLineNumbers=1
autocmd FileType nerdtree setlocal relativenumber
" automatically jump to last line edited on opening a file
autocmd BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | execute "normal! g`\"" | endif
" " remember folding
" autocmd BufWinLeave *.* mkview
" autocmd BufWinEnter *.* silent loadview 
" cursorline nice
augroup CursorLine
    autocmd!
    autocmd VimEnter,WinEnter,BufWinEnter * setlocal cursorline
    autocmd WinLeave * setlocal nocursorline
augroup END
"hi StatusLine   ctermfg=15  guifg=#ffffff ctermbg=239 guibg=#4e4e4e cterm=bold gui=bold
"hi StatusLineNC ctermfg=249 guifg=#b2b2b2 ctermbg=237 guibg=#3a3a3a cterm=none gui=none
set cursorline
" for vs code like persistent terminals
function! ToggleTerminal()
  if exists("t:terminal_buf") && bufexists(t:terminal_buf)
    " If terminal buffer exists, check if it's visible
    let l:winid = bufwinnr(t:terminal_buf)
    if l:winid != -1
      " Hide the terminal buffer instead of closing it
      execute l:winid . "wincmd w"
      execute "hide"
    else
      " Reopen the terminal buffer in a horizontal split
      execute "botright sbuffer " . t:terminal_buf
    endif
  else
    " Open a new terminal and store its buffer number
    botright terminal
    let t:terminal_buf = bufnr('%')
  endif
endfunction
" tab complete for insert mode function
function! Tab_Or_Complete()
  if col('.')>1 && strpart( getline('.'), col('.')-2, 3 ) =~ '^\w'
    return "\<C-N>"
  else
    return "\<Tab>"
  endif
endfunction
set dictionary="/usr/dict/words"
" folds everything except for where I am
function! FoldExceptCursor()
  normal! zM
  normal! zv
endfunction
let s:wrapenabled = 0
function! ToggleWrap()
  set wrap nolist
  if s:wrapenabled
    set nolinebreak
    unmap j
    unmap k
    unmap 0
    unmap ^
    unmap $
    let s:wrapenabled = 0
  else
    set linebreak
    nnoremap j gj
    nnoremap k gk
    nnoremap 0 g0
    nnoremap ^ g^
    nnoremap $ g$
    vnoremap j gj
    vnoremap k gk
    vnoremap 0 g0
    vnoremap ^ g^
    vnoremap $ g$
    let s:wrapenabled = 1
  endif
endfunction
map <leader>w :call ToggleWrap()<CR>
" Define a function that force-closes terminal buffers and then quits Vim.
function! WriteAndForceQuitTerm()
  " First, write all changes in non-terminal buffers.
  wall

  " Now, force-delete all terminal buffers.
  for buf in getbufinfo({'buflisted': 1})
    if getbufvar(buf.bufnr, '&buftype') ==# 'terminal'
      execute 'silent! bdelete! ' . buf.bufnr
    endif
  endfor

  " Finally, quit all.
  qa
endfunction

" Create a command for it
command! WqaTermForce call WriteAndForceQuitTerm()

" Optional: remap :wqa to your function
cabbrev wqa WqaTermForce
let g:airline#extensions#tabline#enabled = 1
" for ripgrep
if executable('rg')
  set grepprg=rg\ --vimgrep
endif
let g:airline#extensions#ale#enabled = 1
let g:airline#extensions#branch#enabled = 1    " turns it on
" ~/.vimrc  ── works in both Vim 8 and Neovim
set hidden

if has('termguicolors')
  set termguicolors
endif

" For dark version.
set background=dark

" Set contrast.
" This configuration option should be placed before `colorscheme everforest`.
" Available values: 'hard', 'medium'(default), 'soft'
let g:everforest_background = 'hard'
colorscheme everforest

" For better performance
let g:everforest_better_performance = 1
" set termguicolors

" let g:tokyonight_style = 'storm' " available: night, storm
" let g:tokyonight_enable_italic = 1
" colorscheme tokyonight
" let g:airline_theme = "tokyonight"
"
let g:ctrlp_working_path_mode = ''
function! s:Bon() abort
  let l:keep = bufnr('%')          " buffer we stay in
  for l:buf in getbufinfo({'buflisted': 1})
        " Skip the current buffer and any :terminal buffer
        if l:buf.bufnr == l:keep
          continue
        endif
        if getbufvar(l:buf.bufnr, '&buftype') !=# 'terminal'
          " Use :bdelete! if you want to wipe even modified files
          execute 'silent! bdelete' l:buf.bufnr
        endif
  endfor
endfunction

command! Bon call <SID>Bon()
command -nargs=* Glg Git! lg <args>
" Pull the version marked LOCAL (i.e. your working copy)
command! -nargs=0 LO diffget LOCAL

" Pull the version marked REMOTE (i.e. the incoming change)
command! -nargs=0 RE diffget REMOTE

set splitright
set wildmenu

hi CursorLine guifg=black guibg=#a7c080
" let g:pydocstring_doq_path = '/home/jeffrey.ke/miniconda3/envs/twin/bin/doq'
cnoremap :s :s/\v
