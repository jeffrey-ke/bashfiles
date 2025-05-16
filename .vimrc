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
nnoremap <Space>d <C-d>
nnoremap <Space>u <C-u>
tnoremap <Esc><Esc> <C-\><C-n>
nnoremap <Space>b :NERDTreeToggle<CR>
nnoremap <Space>t :call ToggleTerminal()<CR>
nnoremap <Space><Space> <C-^>
inoremap <Tab> <C-R>=Tab_Or_Complete()<CR>
nnoremap ff :call FoldExceptCursor()<CR>
nnoremap <Space>a :Ack 
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

" color scheme
colorscheme everforest
" code folding
set foldmethod=indent
set foldnestmax=3
" words now wrap.
set linebreak
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
call plug#end()
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
