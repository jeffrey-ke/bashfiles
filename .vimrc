set number relativenumber
set tabstop=4       " Number of spaces that a <Tab> in the file counts for
set softtabstop=4
set shiftwidth=4    " Number of spaces to use for each step of autoindent
set expandtab       " Convert tabs to spaces
nnoremap <Space>h <C-w>h
nnoremap <Space>l <C-w>l
nnoremap <Space>j <C-w>j
nnoremap <Space>k <C-w>k
tnoremap <Esc> <C-\><C-n>
colorscheme desert
set ttimeoutlen=10
let g:netrw_liststyle=3
nnoremap <Space>b :NERDTreeToggle<CR>

call plug#begin()
Plug 'ryanoasis/vim-devicons'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
call plug#end()
set encoding=utf8
set guifont=AurulentSansMNerdFontMono-Regular\ Nerd\ Font\ 11
let NERDTreeShowLineNumbers=1
autocmd FileType nerdtree setlocal relativenumber
autocmd BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | execute "normal! g`\"" | endif
nnoremap <Space>d <C-d>
nnoremap <Space>u <C-u>
augroup CursorLine
    autocmd!
    autocmd VimEnter,WinEnter,BufWinEnter * setlocal cursorline
    autocmd WinLeave * setlocal nocursorline
augroup END
hi StatusLine   ctermfg=15  guifg=#ffffff ctermbg=239 guibg=#4e4e4e cterm=bold gui=bold
hi StatusLineNC ctermfg=249 guifg=#b2b2b2 ctermbg=237 guibg=#3a3a3a cterm=none gui=none
set cursorline
nnoremap <C-p> :Files<CR>
nnoremap <Space><Space> <C-^>

