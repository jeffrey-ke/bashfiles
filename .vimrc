set number relativenumber
set tabstop=4       " Number of spaces that a <Tab> in the file counts for
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
call plug#end()
set encoding=utf8
set guifont=AurulentSansMNerdFontMono-Regular\ Nerd\ Font\ 11

