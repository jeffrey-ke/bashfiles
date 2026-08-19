#!/bin/bash

# This Mac. hostname -s is `jke-laptop` (ComputerName and LocalHostName agree), and
# no other machines/*.sh regex matches it — machines/jeffpro-3.sh is the *older* Mac,
# whose $papers path does not exist here.

# MacVim is an .app, so its CLI wrappers (mvim, gvim, mview, ...) live inside the
# bundle and are not on PATH. The wrapper passes normal vim flags through to the
# binary and picks its mode from the name it was invoked as, so calling it `mvim`
# keeps the GUI behavior. Mac-only, hence here and not in .bash_aliases (which `aa`
# writes to and every machine sources).
alias mvim='/Applications/MacVim.app/Contents/bin/mvim'
