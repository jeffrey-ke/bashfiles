#!/bin/bash

# Function: db
# Usage: db <image> <tag>
#!/bin/bash

# Function: db
# Usage: db <image> <tag> [--no-cache]
db() {
	# Ensure at least image and tag are provided.
	if [ "$#" -lt 2 ]; then
		echo "Usage: db <image> <tag> [--no-cache]"
		echo "This is a function that builds <image> with <tag>."
		return 1
	fi

	local IMAGE="$1"
	local TAG="$2"
	shift 2

	# Check for an optional --no-cache flag.
	local NO_CACHE_FLAG=""
	for arg in "$@"; do
		if [ "$arg" = "--no-cache" ]; then
			NO_CACHE_FLAG="--no-cache"
		fi
	done

	local DOCKERFILE_DIR="." # Adjust if necessary

	echo "Building Docker image: ${IMAGE}:${TAG}..."
	if ! docker build ${NO_CACHE_FLAG} -t "${IMAGE}:${TAG}" "${DOCKERFILE_DIR}"; then
		echo "❌ Docker build failed. Exiting..."
		return 1
	fi

	# Cleanup dangling images after a successful build.
	echo "Cleaning up dangling images..."
	docker image prune -f
}
drun() {
	if [ "$#" -lt 1 ]; then
		echo "Usage: drun <image> [<directory in docker filesystem to mount to>]"
		echo "This is a function that runs an image and mounts the working directory to /root/ws by default in the container"
		return 1
	fi
	local image="$1"

	local current_dir=$(pwd)
	local docker_path="/root/ws"
	if [ "$#" -eq 2 ]; then
		echo "Mounting to path: $2"
		docker_path="$2"
	fi
	xhost +local:
	docker run --rm -it --privileged \
		--gpus all \
		--device=/dev/bus/usb \
		-e DISPLAY=$DISPLAY -e QT_DEBUG_PLUGINS=1 \
		--network=host \
		-v $XAUTHORITY:$XAUTHORITY \
		-e XAUTHORITY=/tmp/.docker.xauth \
		-v "$current_dir:$docker_path" \
		-v "/dev/bus/usb:/dev/bus/usb" \
		-v /tmp/.X11-unix:/tmp/X11-unix \
		-v /tmp/.docker.xauth:/tmp/.docker.xauth \
		"$image"
}
dsa() {
	if [ -z "$1" ]; then
		echo "Usage: dsa  <container_id_or_name>"
		return 1
	fi

	CONTAINER_ID=$1

	# Check if the container exists
	if ! docker ps -a --format "{{.ID}} {{.Names}}" | grep -q "$CONTAINER_ID"; then
		echo "Error: No such container '$CONTAINER_ID'"
		return 1
	fi

	# Start the container if it's not running
	if ! docker ps --format "{{.ID}}" | grep -q "$CONTAINER_ID"; then
		echo "Starting container '$CONTAINER_ID'..."
		docker start "$CONTAINER_ID"
	fi

	# Attach to the container
	echo "Attaching to container '$CONTAINER_ID'..."
	docker exec -it "$CONTAINER_ID" /bin/bash
}
aa() {
	if [ $# -ne 2 ]; then
		echo "Usage: aa <alias_name> <command>"
		return 1
	fi

	local alias_name="$1"
	local command="$2"

	# Add alias to current session
	alias "$alias_name"="$command"

	# Persist the alias in ~/.bash_aliases (if it exists) or ~/.bashrc
	local alias_file="$HOME/.bash_aliases"
	if [ ! -f "$alias_file" ]; then
		alias_file="$HOME/.bashrc"
	fi
	# Resolve to the file in the repo before writing. run.sh points
	# ~/.bash_aliases at dotfiles/.bash_aliases, and `sed -i` below does not edit
	# in place -- it renames a temp file over its target -- so editing the *link*
	# path replaces the link with a regular file. Nothing looks broken when that
	# happens (the shell still sources it), but the edit never reaches git and
	# every later `aa` accumulates outside the repo until the next run.sh `ln -sf`
	# silently discards the lot. Renaming a regular file over a regular file is
	# fine: the link resolves by path, so it still finds the new content.
	# Degrades to the old behaviour if realpath is missing rather than failing.
	alias_file="$(realpath -- "$alias_file" 2>/dev/null || printf '%s' "$alias_file")"

	# Check if the alias already exists and update it, otherwise append it
	if grep -q "alias $alias_name=" "$alias_file"; then
		sed -i "/alias $alias_name=/c\alias $alias_name='$command'" "$alias_file"
	else
		echo "alias $alias_name='$command'" >>"$alias_file"
	fi

	echo "Alias '$alias_name' added successfully."
	echo "Run 'source $alias_file' or restart your shell to apply it."
}
gso() {
	# Check if a URL was provided
	if [ -z "$1" ]; then
		echo "Usage: gso  <url>"
		echo "This is a function that sets the origin of the current repo."
		return 1
	fi

	# Check if the 'origin' remote already exists
	if git remote | grep -q '^origin$'; then
		# Update the URL for the existing 'origin' remote
		git remote set-url origin "$1"
		echo "Updated origin URL to: $1"
	else
		# Add a new remote named 'origin'
		git remote add origin "$1"
		echo "Added origin remote with URL: $1"
	fi
	git branch --set-upstream-to=origin/main

}
gs() {
	git status
}

# ga() {
# 	git rm -r --cached -f .
# 	git add .
# }

# gc() {
# 	if [ -z "$1" ]; then
#         git commit
# 	fi
# 	git commit -m "$1"
# }

# gp() {
# 	 branch=$(git symbolic-ref --short HEAD)
# 	 remote=$(git config branch."$branch".remote || echo "origin")
# 	 echo "Pushing to $remote/$branch..."
# 	 git push "$remote" "$branch"
# }
gig() {
	# Check if a line was provided
	if [ -z "$1" ]; then
		echo "Usage: gig <line to add>"
		return 1
	fi

	local line="$1"
	# Ensure .gitignore exists
	touch .gitignore

	# Check if the exact line already exists in .gitignore
	if grep -Fxq "$line" .gitignore; then
		echo "Line already exists in .gitignore"
	else
		echo "$line" >>.gitignore
		echo "Line added to .gitignore"
	fi
}
mcd() {
	mkdir -p "$1"
	if [ -d "$1" ]; then
		cd "$1"
	fi
}
unzipthis() {
	for file in *.zip; do
		unzip "$file"
	done
}

dpush() {
	if [[ $# -lt 2 ]]; then
		echo "Needs two args: image and tag"
		return 1
	fi
	image=$1
	tag=$2
	docker tag $image:$tag jeffreyke/$image:$tag
	docker push jeffreyke/$image:$tag
}

# ============================================================================
# Google Drive rclone functions
# Setup instructions:
#   1. Install rclone: sudo apt install rclone
#   2. Run `gsetup` to configure with encrypted config
#   3. For headless OAuth, use carbonyl browser: carbonyl https://accounts.google.com
# ============================================================================

_rclone_password_cmd='read -s -p "rclone password: " p; echo "$p"'
_gdrive_remote="gdrive"
_gdrive_default_folder="uploads"
_gdrive_share_log="$HOME/.gdrive_shares.log"

_rclone_with_password() {
	rclone --password-command "$_rclone_password_cmd" "$@"
}

gsetup() {
	echo "Google Drive rclone setup with encrypted config"
	echo "================================================"
	echo ""
	echo "This will guide you through setting up rclone with an encrypted config."
	echo ""
	echo "Steps:"
	echo "  1. Run: rclone config"
	echo "  2. Choose 'n' for new remote"
	echo "  3. Name it: $_gdrive_remote"
	echo "  4. Choose 'drive' (Google Drive)"
	echo "  5. Leave client_id and client_secret blank (use rclone's)"
	echo "  6. Choose scope: 1 (full access)"
	echo "  7. Leave root_folder_id blank"
	echo "  8. Leave service_account_file blank"
	echo "  9. For 'auto config': n (headless server)"
	echo " 10. Open the provided URL in carbonyl for OAuth"
	echo " 11. Paste the verification code back"
	echo " 12. Choose 'n' for team drive"
	echo " 13. Confirm and quit"
	echo ""
	echo "After basic setup, encrypt the config:"
	echo "  rclone config encryption password"
	echo ""
	read -p "Press Enter to start rclone config..."
	rclone config
}

gcheck() {
	echo "Checking rclone Google Drive configuration..."

	if ! command -v rclone &>/dev/null; then
		echo "ERROR: rclone is not installed"
		echo "Install with: sudo apt install rclone"
		return 1
	fi

	if ! _rclone_with_password listremotes 2>/dev/null | grep -q "^${_gdrive_remote}:$"; then
		echo "ERROR: Remote '$_gdrive_remote' not configured"
		echo "Run 'gsetup' to configure"
		return 1
	fi

	echo "Testing connection to $_gdrive_remote..."
	if _rclone_with_password about "${_gdrive_remote}:" &>/dev/null; then
		echo "SUCCESS: Connected to Google Drive"
		_rclone_with_password about "${_gdrive_remote}:"
		return 0
	else
		echo "ERROR: Could not connect to Google Drive"
		echo "Token may be expired - run 'rclone config reconnect ${_gdrive_remote}:'"
		return 1
	fi
}

gls() {
	local folder="${1:-$_gdrive_default_folder}"
	_rclone_with_password ls "${_gdrive_remote}:${folder}"
}

gshare() {
	if [[ $# -lt 1 ]]; then
		echo "Usage: gshare <file|directory> [folder]"
		echo "Uploads file or directory to Google Drive and returns shareable link"
		echo "Default folder: $_gdrive_default_folder"
		return 1
	fi

	local file="$1"
	local folder="${2:-$_gdrive_default_folder}"

	if [[ ! -e "$file" ]]; then
		echo "ERROR: Not found: $file"
		return 1
	fi

	local filename=$(basename "$file")
	local dest="${_gdrive_remote}:${folder}/${filename}"

	echo "Uploading $filename to $folder..."
	local dest_path="${_gdrive_remote}:${folder}/"
	if [[ -d "$file" ]]; then
		dest_path="${_gdrive_remote}:${folder}/${filename}"
	fi

	if ! _rclone_with_password copy "$file" "$dest_path"; then
		echo "ERROR: Upload failed"
		return 1
	fi

	echo "Creating shareable link..."
	local link
	link=$(_rclone_with_password link "$dest" 2>&1)

	if [[ $? -ne 0 ]]; then
		echo "ERROR: Could not create link"
		echo "$link"
		return 1
	fi

	local timestamp=$(date -Iseconds)
	echo "$timestamp $filename $link" >>"$_gdrive_share_log"

	echo ""
	echo "SUCCESS: $filename uploaded"
	echo "Link: $link"
	echo "(logged to $_gdrive_share_log)"
}

_extract_drive_id() {
	echo "$1" | grep -oP '(?:folders/|file/d/|[?&]id=)\K[A-Za-z0-9_-]+' | head -1
}

_drive_folder_name() {
	curl -sL "$1" | grep -oP '<title>\K[^<]+' | head -1 | sed 's/ - Google Drive$//'
}

gfetch() {
	if [[ $# -lt 1 ]]; then
		echo "Usage: gfetch <drive-url> [dest]"
		echo "Downloads a Google Drive folder or file, preserving its name"
		echo "Default dest: current directory"
		return 1
	fi

	local url="$1"
	local dest="${2:-.}"

	local drive_id
	drive_id=$(_extract_drive_id "$url")
	if [[ -z "$drive_id" ]]; then
		echo "ERROR: Could not extract ID from URL"
		return 1
	fi

	if [[ "$url" == *"/file/d/"* ]]; then
		mkdir -p "$dest"
		echo "Downloading file (id=$drive_id) to ${dest%/}/..."
		if ! _rclone_with_password backend copyid "${_gdrive_remote}:" "$drive_id" "${dest%/}/"; then
			echo "ERROR: Download failed"
			return 1
		fi
		echo ""
		echo "SUCCESS: Downloaded to ${dest%/}/"
		return 0
	fi

	local folder_id="$drive_id"
	local folder_name
	folder_name=$(_drive_folder_name "$url")
	if [[ -z "$folder_name" ]]; then
		echo "WARNING: Could not determine folder name, using ID"
		folder_name="$folder_id"
	fi

	local target="${dest}/${folder_name}"

	echo "Folder: $folder_name"
	echo "Listing contents..."

	local listing
	listing=$(_rclone_with_password ls "${_gdrive_remote}:" --drive-root-folder-id="$folder_id" 2>&1)
	if [[ $? -ne 0 ]]; then
		echo "ERROR: Could not list folder"
		echo "$listing"
		return 1
	fi

	echo "$listing"
	echo ""
	echo "Downloading to $target..."
	mkdir -p "$target"

	if ! _rclone_with_password copy "${_gdrive_remote}:" "$target" --drive-root-folder-id="$folder_id" --progress; then
		echo "ERROR: Download failed"
		return 1
	fi

	echo ""
	echo "SUCCESS: Downloaded to $target"
}

gitdel() {
	git branch -D $1
	git branch -rd origin/$1 2>/dev/null
}

# gtar: upload files/directories to a named folder in Google Drive
# Usage: gtar <gdrive-folder> <path> [path2 ...]
# Example: gtar my-dataset logs/ weights.pt config.yaml
gtar() {
	if [[ $# -lt 2 ]]; then
		echo "Usage: gtar <gdrive-folder> <path> [path2 ...]"
		return 1
	fi

	local folder="$1"
	shift

	for p in "$@"; do
		if [[ ! -e "$p" ]]; then
			echo "ERROR: path not found: $p"
			return 1
		fi
	done

	for p in "$@"; do
		local name
		name=$(basename "$p")
		local dest="${_gdrive_remote}:${folder}/"
		[[ -d "$p" ]] && dest="${_gdrive_remote}:${folder}/${name}"

		echo "Uploading $p -> $_gdrive_remote:${folder}/..."
		if ! _rclone_with_password copy "$p" "$dest" --progress; then
			echo "ERROR: Upload failed for $p"
			return 1
		fi
	done

	echo ""
	echo "Creating shareable link..."
	local link
	link=$(_rclone_with_password link "${_gdrive_remote}:${folder}" 2>&1)
	if [[ $? -ne 0 ]]; then
		echo "WARNING: Could not create link"
		echo "$link"
	else
		local timestamp
		timestamp=$(date -Iseconds)
		echo "$timestamp ${folder} $link" >>"$_gdrive_share_log"
		echo "Link: $link"
		echo "(logged to $_gdrive_share_log)"
	fi

	echo "SUCCESS: all files uploaded to $_gdrive_remote:${folder}/"
}

pydb() {
	python3 -m pdb $1
}

fixdisplay() {
	if [[ -z "$TMUX" ]]; then
		echo "Not in a tmux session"
		return 1
	fi
	for var in DISPLAY WAYLAND_DISPLAY XAUTHORITY; do
		local val
		val=$(tmux show-environment "$var" 2>/dev/null)
		if [[ "$val" == "${var}="* ]]; then
			export "$val"
		fi
	done
	echo "DISPLAY=$DISPLAY"
}

trun() {
	if [[ $# -eq 0 ]]; then
		echo "Usage: trun [session-name] <command...>" >&2
		return 1
	fi

	local name cmd
	if [[ $# -gt 1 && "$1" != *" "* ]]; then
		name="$1"
		shift
	else
		name="${1%% *}"
	fi

	cmd="$*"
	tmux new-session -d -s "$name" \; send-keys -t "$name" "$cmd" Enter &&
		echo "Started '$name'. Attach: tmux attach -t $name"
}
notify() {
	# OSC 777 → Ghostty on Mac (works over SSH). Unambiguous vs OSC 9 (ConEmu progress).
	# Inside tmux, raw OSC is swallowed; DCS passthrough to #{pane_tty} is required
	# (stdout passthrough alone is unreliable). ST terminator — not BEL — avoids a
	# false "ping" when macOS suppresses the banner (focused Ghostty window).
	local body="$1" title="${2:-Terminal}"
	if [ -n "$TMUX" ]; then
		local pane_tty seq
		pane_tty=$(tmux display-message -p '#{pane_tty}' 2>/dev/null)
		seq=$(printf '\033Ptmux;\033\033]777;notify;%s;%s\033\\\033\\' "$title" "$body")
		if [ -n "$pane_tty" ] && [ -w "$pane_tty" ]; then
			printf '%s' "$seq" >"$pane_tty"
		else
			printf '%s' "$seq"
		fi
	else
		printf '\033]777;notify;%s;%s\033\\' "$title" "$body"
	fi
}

notify-test() {
	echo "Ghostty must be UNFOCUSED for a banner (macOS hides them when focused)."
	echo "Also try: System Settings → Notifications → Ghostty → Alerts (not Banners)."
	echo "Sending via notify() (pane_tty + tmux passthrough)..."
	notify "Chain test from tesu tmux" "Ghostty"
}

cc() {
	if [[ $# -lt 1 ]]; then
		echo "Need a path"
		echo "Usage: cc path"
		return 1
	fi
	cd "$1" && claude
}

# scp a file off another host into this machine's papers directory. Lived in
# machines/jeffpro-3.sh with the destination hardcoded, while `alias ot='obgrab tesu'`
# sat in the shared .bash_aliases — so the alias was dead on every other machine. The
# destination is exactly what the path registry below exists for, so it comes from
# $papers; only that assignment is per-machine now.
obgrab() {
	local host="$1" remote_path="$2"
	local name="${3:-$(basename "$remote_path")}"
	if [ -z "$papers" ]; then
		echo "obgrab: \$papers is unset — register this machine's papers directory with: pp <path> papers" >&2
		return 1
	fi
	scp -r "$host:$remote_path" "$papers/$name"
}

# --- path registry: machine-specific long-path -> short $var registry ---
# Mechanism lives here (shared, symlinked). Data lives in a marker block inside
# machines/<hostname>.sh (git-tracked, already sourced by .bashrc) -> per-machine.
# A $var expands in ANY position on the command line (unlike an alias) and
# $name/<TAB> tab-completes subdirs. Register with pp, list pl, remove prm, jump to.
# A registration may be a file as well as a directory (`pp cfg ~/very/deep/conf.yaml`);
# only `to` cares about the difference, and it cd's to a file's parent directory.

_pr_file() { printf '%s\n' "$HOME/dotfiles/machines/$(hostname -s).sh"; }
_pr_begin='# >>> path registry >>>'
_pr_end='# <<< path registry <<<'

# Echo the registered path for $1 (empty if none). Reads only inside the block.
_pr_get() {
	local file
	file="$(_pr_file)"
	[ -f "$file" ] || return 0
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$1" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && $0 ~ ("^export " nm "=") {
			line=$0; sub("^export " nm "=", "", line)
			gsub(/^'\''|'\''$/, "", line); print line; exit
		}' "$file"
}

# Echo registered names, one per line (for completion).
_pr_names() {
	local file
	file="$(_pr_file)"
	[ -f "$file" ] || return 0
	awk -v b="$_pr_begin" -v e="$_pr_end" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && /^export [a-zA-Z_][a-zA-Z0-9_]*=/ {
			line=$0; sub(/^export /, "", line)
			print substr(line, 1, index(line, "=")-1)
		}' "$file"
}

pp() {
	if [ $# -lt 1 ] || [ $# -gt 2 ]; then
		echo "Usage: pp <name> [path]   (path defaults to current dir)"
		return 1
	fi
	local name="$1" raw="${2:-$PWD}"
	if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		echo "Error: '$name' is not a valid variable name."
		return 1
	fi
	# Reject non-existent paths: require an existing file or directory.
	local path
	if ! path="$(realpath -e -- "$raw" 2>/dev/null)"; then
		echo "Error: '$raw' does not exist."
		return 1
	fi
	if type "$name" >/dev/null 2>&1; then
		echo "Warning: '$name' also names a command/alias/function; \$$name still works as a var."
	fi
	if [ -n "${!name+set}" ] && [ -z "$(_pr_get "$name")" ]; then
		echo "Warning: '$name' shadows an existing environment variable."
	fi
	export "$name=$path"

	local file
	file="$(_pr_file)"
	if [ ! -f "$file" ]; then
		mkdir -p -- "$(dirname -- "$file")"
		printf '#!/bin/bash\n' >"$file"
	fi
	if ! grep -qF -- "$_pr_begin" "$file"; then # leading \n: machine file may lack a trailing newline
		printf '\n%s\n%s\n' "$_pr_begin" "$_pr_end" >>"$file"
	fi
	local esc="${path//\'/\'\\\'\'}" line
	line="export $name='$esc'"
	local tmp
	tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" -v ln="$line" '
		$0 == b { inblk=1; print; next }
		$0 == e { if (inblk && !done) print ln; inblk=0; done=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { print ln; done=1; next }
		{ print }' "$file" >"$tmp" && cat -- "$tmp" >"$file"
	rm -f -- "$tmp"
	echo "Registered \$$name -> $path"
	if [ -d "$path" ]; then
		echo "Use anywhere, e.g.: ls \$$name/   cd \$$name   to $name"
	else
		echo "Use anywhere, e.g.: nvim \$$name   cat \$$name   to $name   (cd's to its dir)"
	fi
}

pl() {
	local file
	file="$(_pr_file)"
	if [ ! -f "$file" ] || ! grep -qF -- "$_pr_begin" "$file"; then
		echo "No paths registered on this machine ($(hostname -s)) yet."
		echo "Register one with: pp <name> [path]"
		return 0
	fi
	local pairs
	pairs="$(awk -v b="$_pr_begin" -v e="$_pr_end" '
		$0 == b { inblk=1; next }
		$0 == e { inblk=0; next }
		inblk && /^export [a-zA-Z_][a-zA-Z0-9_]*=/ {
			line=$0; sub(/^export /, "", line); eq=index(line,"=")
			nm=substr(line,1,eq-1); val=substr(line,eq+1)
			gsub(/^'\''|'\''$/, "", val); printf "%s\t%s\n", nm, val
		}' "$file")"
	[ -z "$pairs" ] && {
		echo "No paths registered on this machine ($(hostname -s)) yet."
		return 0
	}
	printf '%s\n' "$pairs" | column -t -s $'\t'
}

prm() {
	[ $# -ne 1 ] && {
		echo "Usage: prm <name>"
		return 1
	}
	local name="$1" file
	file="$(_pr_file)"
	if [ ! -f "$file" ] || [ -z "$(_pr_get "$name")" ]; then
		echo "'$name' is not registered on this machine."
		return 1
	fi
	unset "$name"
	local tmp
	tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" '
		$0 == b { inblk=1; print; next }
		$0 == e { inblk=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { next }
		{ print }' "$file" >"$tmp" && cat -- "$tmp" >"$file"
	rm -f -- "$tmp"
	echo "Removed \$$name from the registry."
}

to() {
	[ $# -ne 1 ] && {
		echo "Usage: to <name>"
		return 1
	}
	local name="$1"
	[ -z "${!name+set}" ] && {
		echo "Error: \$$name is not set (try: pl)."
		return 1
	}
	local target="${!name}"
	# A file registration jumps to its containing directory -- `to` is the only
	# consumer that needs a directory; every other use ($name splatted into a
	# command line) wants the file path itself.
	[ -f "$target" ] && target="$(dirname -- "$target")"
	[ ! -d "$target" ] && {
		echo "Error: \$$name -> '${!name}' is not a file or directory."
		return 1
	}
	builtin cd -- "$target" # bypass the zoxide cd() wrapper for a deterministic jump
}

_pr_complete() {
	local cur="${COMP_WORDS[COMP_CWORD]}"
	COMPREPLY=($(compgen -W "$(_pr_names)" -- "$cur"))
}
complete -F _pr_complete to
complete -F _pr_complete prm

# --- repo root: gx <repo-relative path> -> absolute path ---
# Lets a path be typed the way it is written down (in a PR, a BUILD label, a grep
# hit) from any subdirectory: nvim "$(gx perception/labeling/foo.py)". No argument
# echoes the root itself. Fails loudly outside a repo -- git's own message, on stderr.
gx() {
	local top
	top=$(git rev-parse --show-toplevel) || return 1
	printf '%s\n' "$top${1:+/$1}"
}

# $root is gx with no typing: bash expands a $var before filename completion (but will
# never run a command substitution to do it), so `nvim $root/perc<TAB>` completes from
# the root while `$(gx perc<TAB>` completes from $PWD. Same deal as the path registry
# above, only the value tracks $PWD's checkout instead of being fixed per machine.
#
# Refreshed per prompt rather than from the cd() wrapper, because zoxide's z() and
# pushd both reach a new directory without passing through it. Outside a repo $root
# names a path that cannot exist, so a habit-typed command fails loudly instead of
# quietly resolving against /. Not exported: a typing aid, not environment for
# children -- and $root is a name build systems help themselves to.
_root_var() { root=$(gx 2>/dev/null) || root=/dev/null/not-in-a-git-repo; }
_root_var
# Guarded because `fresh` re-sources .bashrc; array-aware because bash-git-prompt may
# leave either shape (it appends to what it finds, so arriving first is fine).
if [[ "${PROMPT_COMMAND[*]}" != *_root_var* ]]; then
	if declare -p PROMPT_COMMAND &>/dev/null && [[ $(declare -p PROMPT_COMMAND) == "declare -a"* ]]; then
		PROMPT_COMMAND+=('_root_var')
	else
		PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_root_var"
	fi
fi

# --- snippet alias registry: short key -> a plaintext string you can't spell ---
# Mechanism here; data in ~/.snippet_aliases. Unlike the path registry above this is
# NOT machine-specific -- a flag name is spelled the same everywhere -- so the data
# lives in one git-tracked file rather than in machines/<hostname>.sh. That file has
# two readers: .bashrc sources it (so `$key` expands on the command line, unexported)
# and nvim/luasnippets/all.lua parses it into a snippet active in every filetype.
# Register with sa, list sl, remove srm -- the sibling of the path registry's pp/pl/prm.

_sa_file() { printf '%s\n' "$HOME/.snippet_aliases"; }

# The one regex all three helpers key off. `[^ \t]` after the `=` mirrors what bash
# accepts and what all.lua enforces: `k = v` runs `k` as a command, `k= v` assigns
# empty and runs `v`, so neither is an entry. `export` is tolerated, not required.
_sa_re='^[ \t]*(export[ \t]+)?%s=[^ \t]'

# Echo the registered value for $1 (empty if none). bash itself does the parsing:
# sourcing in a subshell is the only reader guaranteed to agree with what the
# interactive shell sees, and it keeps the quote rules (including the `'\''` idiom
# `sa` writes) in one place instead of a third copy alongside awk and all.lua.
# Last assignment wins, because that is simply what sourcing does.
_sa_get() {
	local file
	file="$(_sa_file)"
	[ -f "$file" ] || return 0
	(
		# The subshell inherits the caller's environment, so without this an
		# ordinary env var would come back looking like a registered alias --
		# and `sa` would report an update where it is really a first register.
		unset -v "$1" 2>/dev/null
		source "$file" 2>/dev/null
		printf '%s' "${!1-}"
	)
}

# Echo `key<TAB>value` for every registered alias, in first-appearance order with
# the last value, matching what a shell that sourced the file would hold. One
# subshell for the whole file rather than one _sa_get per key.
_sa_pairs() {
	local file
	file="$(_sa_file)"
	[ -f "$file" ] || return 0
	(
		source "$file" 2>/dev/null
		while IFS= read -r k; do
			printf '%s\t%s\n' "$k" "${!k-}"
		done < <(_sa_names)
	)
}

# Echo registered keys, one per line (for completion).
_sa_names() {
	local file
	file="$(_sa_file)"
	[ -f "$file" ] || return 0
	awk -v re="$(printf "$_sa_re" "[a-zA-Z_][a-zA-Z0-9_]*")" '
		$0 ~ re {
			line=$0; sub(/^[ \t]*/, "", line); sub(/^export[ \t]+/, "", line)
			print substr(line, 1, index(line, "=")-1)
		}' "$file" | awk '!seen[$0]++'
}

sa() {
	if [ $# -ne 2 ]; then
		echo "Usage: sa <key> <value>   (text alias for \$key in bash and a snippet in nvim)"
		return 1
	fi
	local name="$1" value="$2"
	if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		echo "Error: '$name' is not a valid variable name."
		return 1
	fi
	if [ -z "$value" ]; then
		echo "Error: value is empty (nothing to expand to)."
		return 1
	fi
	# One entry is one line in both readers. A newline would split it, leaving the
	# tail as a stray line that bash then tries to run as a command.
	case "$value" in
	*$'\n'*)
		echo "Error: value contains a newline; one alias must fit on one line."
		return 1
		;;
	esac

	local previous
	previous="$(_sa_get "$name")"
	if [ -z "$previous" ] && [ -n "${!name+set}" ]; then
		echo "Warning: '$name' shadows an existing shell variable (was: ${!name})."
	fi

	# printf -v rather than `declare -g` (bash 4.2+): macOS still ships bash 3.2.
	# Unexported on purpose -- see the header comment on ~/.snippet_aliases.
	printf -v "$name" '%s' "$value"

	local file
	file="$(_sa_file)"
	if [ ! -f "$file" ]; then
		echo "Warning: $file did not exist; creating it outside the repo. Run ./run.sh to symlink it."
		printf '# Text aliases: key=value, read by .bashrc and nvim/luasnippets/all.lua.\n' >"$file"
	fi
	local esc="${value//\'/\'\\\'\'}" line
	line="$name='$esc'"
	local tmp
	tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	# First match is rewritten, later duplicates dropped, so this also collapses a
	# hand-edited dupe. `cat >` at the end, never `sed -i`/`mv`: those replace the
	# path, and $file is the ~/.snippet_aliases symlink into the repo -- rewriting
	# it in place is what keeps the edit landing in git instead of orphaning it in
	# $HOME. (`aa` gets this wrong on ~/.bash_aliases.)
	awk -v re="$(printf "$_sa_re" "$name")" -v ln="$line" '
		$0 ~ re { if (!done) { print ln; done = 1 } ; next }
		{ print }
		END { if (!done) print ln }' "$file" >"$tmp" && cat -- "$tmp" >"$file"
	rm -f -- "$tmp"

	if [ -n "$previous" ]; then
		echo "Updated \$$name: '$previous' -> '$value'"
	else
		echo "Registered \$$name -> '$value'"
	fi
	echo "Use: echo \$$name   or type '$name' in nvim (any filetype) and press Enter."
	echo "This shell has it now; nvim needs <leader>rs, other shells a restart."
}

sl() {
	local pairs
	pairs="$(_sa_pairs)"
	if [ -z "$pairs" ]; then
		echo "No text aliases registered yet."
		echo "Register one with: sa <key> <value>"
		return 0
	fi
	# Tab-separated, like `pl`: the separator has to be something a value can
	# contain freely, and these values are full of spaces.
	printf '%s\n' "$pairs" | column -t -s $'\t'
}

srm() {
	if [ $# -ne 1 ]; then
		echo "Usage: srm <key>   (remove a text alias; \`sl\` lists them)"
		return 1
	fi
	local name="$1"
	if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		echo "Error: '$name' is not a valid variable name."
		return 1
	fi
	# Existence is decided by _sa_names, not by _sa_get: a hand-written `k=''`
	# is a line the awk rewrite below would delete, but sourcing it yields the
	# empty string, so _sa_get cannot tell it from an unregistered key.
	if ! _sa_names | grep -qxF -- "$name"; then
		echo "'$name' is not a registered text alias."
		return 1
	fi
	# Read the value first, so the confirmation line doubles as the undo command.
	local previous
	previous="$(_sa_get "$name")"

	local file
	file="$(_sa_file)"
	# Unsets rather than restores: if this key shadowed a real environment
	# variable, that variable is gone from this shell too (a new shell has it
	# back). Same trade prm makes, and the warning sa prints on register is
	# where that gets flagged.
	unset -v "$name"

	local tmp
	tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	# No `done` guard, unlike sa: every matching line goes, so a file
	# hand-edited into duplicates comes out clean. `cat >` for the same reason
	# as sa -- $file is the ~/.snippet_aliases symlink, and sed -i / mv would
	# replace the path and strand the edit in $HOME instead of the repo.
	awk -v re="$(printf "$_sa_re" "$name")" '$0 ~ re { next } { print }' \
		"$file" >"$tmp" && cat -- "$tmp" >"$file"
	rm -f -- "$tmp"

	# The undo line is meant to be pasted back, so the value takes the same
	# close-escape-reopen treatment sa gives it before writing the file --
	# otherwise a value containing a quote prints as invalid bash.
	echo "Removed \$$name (was: '$previous')"
	echo "Undo with: sa $name '${previous//\'/\'\\\'\'}'"
	echo "Gone from this shell; nvim needs <leader>rs, other shells a restart."
}

_sa_complete() {
	# Keys on the first argument only -- the second is free text, not a key.
	[ "$COMP_CWORD" -eq 1 ] || return 0
	local cur="${COMP_WORDS[COMP_CWORD]}"
	COMPREPLY=($(compgen -W "$(_sa_names)" -- "$cur"))
}
complete -F _sa_complete sa
complete -F _sa_complete srm

# --- artifact registry: dataset / asset / checkpoint over HF (see `art`) ---
# Thin wrappers over the `art` tool (~/dotfiles/bin/art, on PATH). Each namespace
# is one HF repo; `art` reads the nearest .artifacts.yaml up-tree. ls/pull/push.
dsl() { art ls dataset; }
dspull() { art pull dataset "$@"; }
dspush() { art push dataset "$@"; }
asl() { art ls asset; }
aspull() { art pull asset "$@"; }
aspush() { art push asset "$@"; }
ckl() { art ls checkpoint; }
ckpull() { art pull checkpoint "$@"; }
ckpush() { art push checkpoint "$@"; }

# --- run registry: training runs over PSC rsync/ssh (see `run`, sibling of `art`) ---
# Thin wrappers over the `run` tool (~/dotfiles/bin/run, on PATH). One remote (psc) in .runs.yaml.
rls() { run list psc; }
rpull() { run pull psc "$@"; }
rpush() { run push psc "$@"; }
rlocal() { run local "$@"; }
# seg-model lives in the model project's venv, not on PATH — pin it so it works from anywhere,
# e.g. `seg-model create t40 --from-run $(run path m2f-fullgrid-hpo-v3/t40)`.
seg-model() { uv run --project ~/repo/refseg-workspace/model seg-model "$@"; }

gpu1() { interact -p GPU-shared --gres=gpu:v100-32:1 -t "${1:-1}:00:00"; }
gpu2() { interact -p GPU-shared --gres=gpu:l40s-48:2 -t "${1:-1}:00:00"; }

# --- fuzzy git commit search (see fgc) ---
# Pickaxe (-G, regex, case-insensitive) prefilters commits whose diff touched
# <pattern>; fzf fuzzy-narrows the oneline candidate list. Enter prints the
# selected hash to stdout for piping (fgc mlflow | xargs git show).
fgc() {
	[ -z "$1" ] && {
		echo "Usage: fgc <pattern>"
		return 1
	}
	local pattern="$1"
	git log --all -G"$pattern" -i --color=always \
		--format='%C(auto)%h%d %s %C(black)%C(bold)%cr' |
		fzf --ansi --no-sort --reverse \
			--preview 'git show --color=always {1}' |
		grep -oE '[a-f0-9]{7,40}' | head -1
}

# --- ug's -Q TUI -> nvim quickfix (see ug) ---
# Same live TUI as the `ug` alias (-Q -Z: type pattern, live fuzzy results), plus
# a quickfix handoff: Enter = selection mode, Enter/Del toggle lines, A = all,
# Ctrl-Q = exit and print selected rows. The TUI draws on /dev/tty (verified in
# ugrep 5.0 screen.cpp), so $(...) only captures that final output. -e seeds the
# pattern (with -Q, positional args are files); -H --no-heading
# --no-initial-tab keeps rows as file:line:col:text (unpadded, filename even
# for a single file) to match nvim's default errorformat; sed strips the SGR
# codes -Q's forced --color=always leaves in the output. Quitting with no
# selection falls back to ALL matches of the seeded pattern (batch re-run of
# the original seed — a pattern typed/refined live in the TUI isn't
# recoverable after exit, so bare ugq just returns; use Enter,A,Ctrl-Q for
# select-all there). The fallback also fires on Esc, so bail with :qa!.
ugq() {
	local out pattern=
	if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
		pattern="$1"
		shift
	fi
	out=$(command ug -Q -Z -n -k -H --no-heading --no-initial-tab ${pattern:+-e "$pattern"} "$@" |
		sed $'s/\x1b\\[[0-9;]*[mK]//g')
	if [ -z "$out" ] && [ -n "$pattern" ]; then
		out=$(command ug -Z -n -k -H --no-heading --no-initial-tab -e "$pattern" "$@")
	fi
	[ -n "$out" ] || return 0
	nvim -q <(printf '%s\n' "$out") -c 'cwindow'
}
# fzf-pick a file and open it in nvim; with an argument, seed fd with it as a
# filename pattern. The selection travels by command substitution, not a pipe
# into xargs: GNU xargs redirects its child's stdin to /dev/null (that is what
# -o exists to undo), so nvim would come up without a terminal. fzf draws on
# /dev/tty regardless, so capturing its stdout costs nothing, and $? is fzf's
# own status here -- inside a pipeline it is not, since the stages run
# concurrently. 1 (no match) and 130 (Esc/Ctrl-C) both fall out through
# || return.
fvim() {
	local sel
	if [[ -n "$1" ]]; then
		sel=$(fd --follow -H --no-ignore --type f "$1" | fzf) || return
	else
		sel=$(fd --type f | fzf) || return
	fi
	[[ -n "$sel" ]] && nvim "$sel"
}

# A scratch file opened in nvim, its path echoed on stdout for a caller to pick
# up. `vimtemp md` suffixes it `.md` so filetype detection works -- and with it
# highlighting, the luasnippets for that filetype, and conform's formatter. Bare
# `vimtemp` leaves it extension-less, for when the content should decide: nvim
# reads a shebang when there is no suffix to go on. A leading dot is tolerated,
# so `vimtemp .md` and `vimtemp md` are the same request.
#
# nvim is handed the terminal explicitly, because the path goes out on stdout and
# a caller therefore runs this inside `$(...)`. nvim's stdout *is* its UI --
# escape sequences and screen contents, not messages -- and unlike fzf it does
# not fall back to /dev/tty when stdout is a pipe. Without the redirection the
# command substitution swallows the whole TUI: a blank screen, an invisible nvim
# still reading keys from the tty, and kilobytes of escapes in the captured
# path. Same trap as the pager in bgfind.
vimtemp() {
	local ext=${1#.}
	local file
	if [[ -n "$ext" ]]; then
		file=$(mktemp -t "vimtemp.XXXXXX.$ext") || return 1
	else
		file=$(mktemp -t "vimtemp.XXXXXX") || return 1
	fi
	if ! nvim "$file" </dev/tty >/dev/tty; then
		rm -f "$file"
		return 1
	fi
	echo "$file"
}

# Write a job in nvim, then hand it to bgrun under a name. `sh` is explicit
# rather than left to vimtemp's default: bgrun reads the file as shell either
# way (it copies the contents into cmd.sh and checks them with `bash -n`), but
# the extension is what gets the buffer syntax highlighting and the sh snippets
# while you are still writing it.
vimrun() {
	if [[ $# -ne 1 ]]; then
		echo "Usage: vimrun <session-name>   (write a job in nvim, then bgrun it)"
		return 1
	fi
	local file
	file=$(vimtemp sh) || { echo "vimtemp failed; nothing spawned" >&2 && return 1; }
	bgrun -n "$1" "$file"
}
_z_usage() {
	cat >&2 <<-'EOF'
		Usage: z [-s|-m|-h] [-k GRACE] [-S SIG] <duration> <command> [args...]

		  z 1 n nv2 --enable-comms    run for one hour -- a bare number is hours
		  z -s 30 ./poll-once         seconds
		  z -m 90 pytest -x           minutes
		  z 45m ./train.py            an explicit s/m/h/d suffix works too

		  -k GRACE   SIGKILL this long after the first signal (default 10s)
		  -S SIG     send SIG instead of TERM (-S INT to imitate Ctrl-C)
	EOF
}

# Seconds from a duration in timeout/systemd syntax (30s, 90m, 1.5h, 2d). Only
# used to decide whether the limit is what ended the run, so integer truncation
# of something like 1.5s is immaterial.
_z_secs() {
	awk -v d="$1" 'BEGIN {
		u = substr(d, length(d)); n = d + 0
		if (u == "m") n *= 60
		else if (u == "h") n *= 3600
		else if (u == "d") n *= 86400
		printf "%d", n
	}'
}

# Is there a user systemd instance to hang a transient cgroup off? The bus socket
# is the test rather than `systemctl --user is-system-running`, which exits
# non-zero for a merely *degraded* instance that would still run a scope fine.
_z_have_scope() {
	[[ -S ${XDG_RUNTIME_DIR:-/nonexistent}/bus ]] && command -v systemd-run >/dev/null 2>&1
}

# The pid + command line of everything still inside a scope's cgroup. This is the
# answer to "what am I waiting for", and it is worth printing: if a build tool's
# long-lived server got started inside the cgroup, it is listed here and the
# limit will eventually kill it too.
_z_scope_tasks() {
	local cg procs pids
	cg=$(systemctl --user show -p ControlGroup --value "$1" 2>/dev/null)
	[[ -n $cg ]] || return 1
	procs="/sys/fs/cgroup${cg}/cgroup.procs"
	[[ -r $procs ]] || return 1
	pids=$(tr '\n' ',' <"$procs")
	pids=${pids%,}
	[[ -n $pids ]] || return 1
	ps -o pid=,args= -p "$pids" 2>/dev/null
}

# Is the scope still running anything? `systemctl is-active` is the wrong test and
# fails in the one direction that matters: the instant the cap fires the unit enters
# **deactivating**, where is-active already answers no while every process in the
# cgroup is still running its exit path. For a glog-linked app that path is a SIGTERM
# handler symbolizing a stack trace, which takes seconds -- so z returned, bash drew a
# prompt, and the trace landed on top of it. That is the symptom this whole function
# exists to prevent, reintroduced at the last second of the run.
_z_scope_live() {
	local st
	st=$(systemctl --user show -p ActiveState --value "$1" 2>/dev/null)
	[[ -n $st && $st != inactive && $st != failed ]]
}

# Reads dur/grace/sig from its caller's locals -- bash locals are visible to
# callees, the same dynamic scoping _source_path_aliases relies on in .bash_tools.
#
# A cgroup is the only container a process *tree* cannot leave. timeout(1) waits
# on and signals its direct child alone, so a launcher that forks the real work
# and exits -- nuro-cli's `n nv2 --enable-comms` does exactly that -- makes
# timeout return in milliseconds with status 0, the limit never applies, and the
# orphan keeps writing to the tty underneath a returned prompt. That was the bug
# this path exists to fix. systemd enforces RuntimeMaxSec against every task in
# the cgroup, so forking, double-forking and setsid all fail to escape it.
#
# Two properties fall out of the cap living in systemd rather than in z. The
# limit outlives z, so Ctrl-C while waiting gives the prompt back *without*
# losing the deadline; and KillMode defaults to control-group for a scope, so the
# signal reaches the whole tree instead of only the process z happened to spawn.
_z_scope() {
	local unit="z-$$-$RANDOM.scope" t0=$SECONDS rc
	systemd-run --user --scope --quiet --collect --unit="$unit" \
		--property=RuntimeMaxSec="$dur" \
		--property=TimeoutStopSec="$grace" \
		--property=KillSignal="SIG${sig#SIG}" \
		-- "$@"
	rc=$?

	# A still-active scope means the command left work behind. Hold the terminal
	# until the cgroup drains: a returned prompt with the job still printing into
	# it is the symptom, not merely untidy.
	if _z_scope_live "$unit"; then
		local interrupted="" announced="" tasks
		tasks=$(_z_scope_tasks "$unit")
		echo "z: '$1' exited but left these running:" >&2
		[[ -n $tasks ]] && sed 's/^/  /' <<<"$tasks" >&2
		echo "z: holding until they finish or hit $dur -- Ctrl-C returns the prompt, the limit still fires" >&2
		trap 'interrupted=1' INT
		while _z_scope_live "$unit"; do
			[[ -n $interrupted ]] && break
			# Say so once on the way into teardown. Without this the only thing on
			# screen is whatever the dying program prints -- for nv2, a glog SIGTERM
			# stack trace that reads exactly like a crash.
			if [[ -z $announced ]] &&
				[[ $(systemctl --user show -p ActiveState --value "$unit" 2>/dev/null) == deactivating ]]; then
				announced=1
				echo "z: limit reached -- SIG$sig sent to the whole cgroup, SIGKILL in $grace; waiting for it to go" >&2
			fi
			sleep 2
		done
		trap - INT
		if [[ -n $interrupted ]]; then
			echo "z: stopped waiting; systemd still ends it at $dur" >&2
			return 130
		fi
	fi

	# The limit is systemd's, so there is no 124 from timeout to read it off --
	# elapsed time is the signal. Report the same 124 anyway, so the documented
	# "124 means it timed out" holds whichever path ran and `z 1 thing || retry`
	# does not silently treat a killed run as a clean one.
	if ((SECONDS - t0 >= $(_z_secs "$dur"))); then
		echo "z: hit the $dur limit" >&2
		return 124
	fi
	return $rc
}

# The portable path: macOS, and PSC compute nodes inside a Slurm job, have no
# user systemd instance. --foreground is what makes it usable interactively --
# without it timeout puts the child in its own process group, so Ctrl-C from the
# terminal never reaches it and it is stopped by SIGTTIN/SIGTTOU the first time
# it reads the tty. The flag's documented cost is exactly why the scope path is
# preferred where it exists: only the direct child is ever signalled, so a
# forking launcher escapes the limit here. That is fine for what actually runs on
# those machines -- training scripts that stay in the foreground -- and wrong for
# a launcher, so prefer a scope when you have one.
_z_timeout() {
	local timeout_bin rc
	timeout_bin=$(command -v timeout || command -v gtimeout) || {
		echo "z: no timeout(1) -- it comes from GNU coreutils (macOS: brew install coreutils)" >&2
		return 127
	}
	"$timeout_bin" --foreground -k "$grace" -s "$sig" "$dur" "$@"
	rc=$?
	((rc == 124 || rc == 137)) && echo "z: hit the $dur limit" >&2
	return $rc
}

# Run something under a wall-clock limit, then kill it.
#
#   z 1 n nv2 --enable-comms     one hour, then shut the whole tree down
#
# -k is on by default because SIGTERM is a request: a program that traps and
# ignores it outlives the limit, which defeats the point of asking for one.
# Every exit status other than the interrupted-while-waiting 130 is the command's
# own, so `z 5m make && deploy` still means what it reads like.
z() {
	local tunit=h grace=10s sig=TERM dur=""
	# The loop does not stop at the duration, so `z -s 30 -k 5 cmd` and
	# `z -k 5 -s 30 cmd` are the same request -- `-s` reads as if it took the
	# number, and writing the two flags in the order they come to mind should not
	# quietly hand `-k 5` to the command as argv. Instead the first bare word is
	# the duration and the second ends the loop, which is unambiguous because a
	# command name never starts with a dash; its own flags come after it and are
	# never seen here.
	while (($#)); do
		case "$1" in
		-s) tunit=s ;;
		-m) tunit=m ;;
		-h) tunit=h ;;
		-k)
			grace="$2"
			shift
			;;
		-S)
			sig="$2"
			shift
			;;
		--help)
			_z_usage
			return 0
			;;
		--)
			shift
			break
			;;
		*)
			[[ -n $dur ]] && break
			dur="$1"
			;;
		esac
		shift
	done

	if [[ -z $dur ]] || (($# == 0)); then
		_z_usage
		return 1
	fi

	# A bare number takes the unit flag (hours by default); a suffixed one is
	# already in the syntax both timeout and systemd accept, and goes through
	# untouched. Validated here rather than left to either of them, whose
	# complaint about a typo'd duration names neither z nor the command that
	# never ran.
	if [[ $dur =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		dur="$dur$tunit"
	elif [[ ! $dur =~ ^[0-9]+(\.[0-9]+)?[smhd]$ ]]; then
		echo "z: '$dur' is not a duration (try 1, 30, 45m, 1.5h)" >&2
		return 1
	fi

	echo "z: $dur limit on: $*" >&2
	if _z_have_scope; then
		_z_scope "$@"
	else
		_z_timeout "$@"
	fi
}

# sparse_worktree, worktree_diff, worktree_apply, ...: draft a change in a throwaway worktree.
# Lives with the Claude skill that drives it.
_sw="$HOME/dotfiles/claude-skills/previewing-changes-in-worktrees/scripts/sparse_worktree.sh"
[ -f "$_sw" ] && source "$_sw"
unset _sw
