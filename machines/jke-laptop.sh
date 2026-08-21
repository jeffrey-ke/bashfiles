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

# `sb` — open the desktop's SilverBullet work log from this Mac, in one command:
# ensure the server is up over there, forward its port here, open the browser.
#
# The counterpart to jke-desktop.sh's `sb`, which starts the server. Same verb on both
# machines, because "get me to my notes" is the same intent from either end.
sb() {
	local port=${SB_PORT:-3030} host=${SB_HOST:-jke-desktop}

	# sb-up is idempotent, so this is safe to run on every invocation. Called by
	# absolute path: an `ssh host cmd` shell never sources .bashrc, so ~/.local/bin
	# is not on PATH over there.
	ssh "$host" '~/.local/bin/sb-up' || return 1

	# The server binds 127.0.0.1 on the desktop and so has no network address of its
	# own — this forward is the only route in. Reuse an existing tunnel instead of
	# stacking a second ssh; ExitOnForwardFailure turns a taken local port into a
	# failure rather than a connection that silently forwards nothing.
	if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
		ssh -f -N -o ExitOnForwardFailure=yes -L "$port:127.0.0.1:$port" "$host" || return 1
	fi

	open "http://localhost:$port"
}

# The admin password is a random string living only on the desktop; put it on the
# clipboard rather than on screen for the one-time browser login.
sbpw() {
	ssh "${SB_HOST:-jke-desktop}" 'cat ~/.config/silverbullet/admin-password' | pbcopy &&
		echo "SilverBullet password copied to clipboard (user: jke)"
}

# `sbj` — edit the work log in nvim instead of the browser, for snippets, spell
# check and the rest of the editor. Takes a page name, or a date, or nothing (today):
#   sbj                     -> Journal/<today>.md      sbj 2026-08-19 -> that entry
#   sbj vlm-triage-work     -> a root page
#
# nvim runs *on the desktop*, over ssh, rather than editing scp:// paths from here.
# netrw's scp:// works (fetch on open, whole-file scp on write) but is not a
# filesystem, so telescope and rg cannot walk it — find_files spawns fd with the URL
# as a cwd and dies. Over ssh the space is a real directory and the whole editor
# works on it unchanged; `cd` first is what makes <leader>sf/<leader>sg search the
# space. Both machines share this nvim config, so the snippets and the tracked
# spellfile are the same ones — as long as the desktop's dotfiles are current.
#
# `bash -ic`, not a bare command: ssh runs the latter through a *non-interactive*
# shell, where Ubuntu's .bashrc early-exits before .bash_tools and leaves
# ~/.local/bin off PATH. nvim, rg and fd all live there. Hardcoding PATH here
# would work but would duplicate what .bash_tools already knows; -i just sources
# it. Only rg's absence is quiet — telescope's find_files falls back from fd to
# find and looks healthy while live_grep silently cannot run.
# -t is needed for the pty (nvim is a TUI, and without one `bash -i` also warns
# about job control), and it is what lets nvim's OSC 52 yanks reach this Mac's
# pasteboard through tmux.
sbj() {
	local page=${1:-}
	case "$page" in
	'') page="Journal/$(date +%F)" ;; # today, by *this* machine's clock
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) page="Journal/$page" ;;
	esac
	# Single-quoted inside double quotes: $page expands here, ~ and $HOME expand
	# over there. Page names contain spaces ("vim dump aug20"), hence the quoting.
	ssh -t "${SB_HOST:-jke-desktop}" "bash -ic 'cd ~/worklog && exec nvim \"$page.md\"'"
}

# Tear the forward down — the tunnel is backgrounded (ssh -f), so it has no terminal
# to Ctrl-C and otherwise survives until the connection drops.
sbdown() {
	pkill -f "ssh -f -N -o ExitOnForwardFailure=yes -L ${SB_PORT:-3030}:127.0.0.1:${SB_PORT:-3030}" &&
		echo "tunnel closed" || echo "no tunnel found"
}
