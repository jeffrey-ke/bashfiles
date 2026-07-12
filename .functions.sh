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

    local DOCKERFILE_DIR="."  # Adjust if necessary

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
        -e DISPLAY=$DISPLAY\
        -e QT_DEBUG_PLUGINS=1 \
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

    # Check if the alias already exists and update it, otherwise append it
    if grep -q "alias $alias_name=" "$alias_file"; then
        sed -i "/alias $alias_name=/c\alias $alias_name='$command'" "$alias_file"
    else
        echo "alias $alias_name='$command'" >> "$alias_file"
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
        echo "$line" >> .gitignore
        echo "Line added to .gitignore"
    fi
}
mcd(){
    mkdir -p "$1"
    if [ -d "$1" ]; then
        cd "$1"
    fi
}
unzipthis(){
    for file in *.zip; do
        unzip "$file"
    done
}

dpush(){
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

    if ! command -v rclone &> /dev/null; then
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
    echo "$timestamp $filename $link" >> "$_gdrive_share_log"

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

    local folder="$1"; shift

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
        echo "$timestamp ${folder} $link" >> "$_gdrive_share_log"
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
    name="$1"; shift
  else
    name="${1%% *}"
  fi

  cmd="$*"
  tmux new-session -d -s "$name" \; send-keys -t "$name" "$cmd" Enter && \
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

# --- path registry: machine-specific long-path -> short $var registry ---
# Mechanism lives here (shared, symlinked). Data lives in a marker block inside
# machines/<hostname>.sh (git-tracked, already sourced by .bashrc) -> per-machine.
# A $var expands in ANY position on the command line (unlike an alias) and
# $name/<TAB> tab-completes subdirs. Register with pp, list pl, remove prm, jump to.

_pr_file() { printf '%s\n' "$HOME/dotfiles/machines/$(hostname -s).sh"; }
_pr_begin='# >>> path registry >>>'
_pr_end='# <<< path registry <<<'

# Echo the registered path for $1 (empty if none). Reads only inside the block.
_pr_get() {
	local file; file="$(_pr_file)"; [ -f "$file" ] || return 0
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
	local file; file="$(_pr_file)"; [ -f "$file" ] || return 0
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
		echo "Usage: pp <name> [path]   (path defaults to current dir)"; return 1
	fi
	local name="$1" raw="${2:-$PWD}"
	if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		echo "Error: '$name' is not a valid variable name."; return 1
	fi
	# Reject non-existent paths: require an existing directory.
	local path
	if ! path="$(realpath -e -- "$raw" 2>/dev/null)" || [ ! -d "$path" ]; then
		echo "Error: '$raw' is not an existing directory."; return 1
	fi
	if type "$name" >/dev/null 2>&1; then
		echo "Warning: '$name' also names a command/alias/function; \$$name still works as a var."
	fi
	if [ -n "${!name+set}" ] && [ -z "$(_pr_get "$name")" ]; then
		echo "Warning: '$name' shadows an existing environment variable."
	fi
	export "$name=$path"

	local file; file="$(_pr_file)"
	if [ ! -f "$file" ]; then
		mkdir -p -- "$(dirname -- "$file")"; printf '#!/bin/bash\n' > "$file"
	fi
	if ! grep -qF -- "$_pr_begin" "$file"; then            # leading \n: machine file may lack a trailing newline
		printf '\n%s\n%s\n' "$_pr_begin" "$_pr_end" >> "$file"
	fi
	local esc="${path//\'/\'\\\'\'}" line
	line="export $name='$esc'"
	local tmp; tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" -v ln="$line" '
		$0 == b { inblk=1; print; next }
		$0 == e { if (inblk && !done) print ln; inblk=0; done=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { print ln; done=1; next }
		{ print }' "$file" > "$tmp" && cat -- "$tmp" > "$file"
	rm -f -- "$tmp"
	echo "Registered \$$name -> $path"
	echo "Use anywhere, e.g.: ls \$$name/   cd \$$name   to $name"
}

pl() {
	local file; file="$(_pr_file)"
	if [ ! -f "$file" ] || ! grep -qF -- "$_pr_begin" "$file"; then
		echo "No paths registered on this machine ($(hostname -s)) yet."
		echo "Register one with: pp <name> [path]"; return 0
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
	[ -z "$pairs" ] && { echo "No paths registered on this machine ($(hostname -s)) yet."; return 0; }
	printf '%s\n' "$pairs" | column -t -s $'\t'
}

prm() {
	[ $# -ne 1 ] && { echo "Usage: prm <name>"; return 1; }
	local name="$1" file; file="$(_pr_file)"
	if [ ! -f "$file" ] || [ -z "$(_pr_get "$name")" ]; then
		echo "'$name' is not registered on this machine."; return 1
	fi
	unset "$name"
	local tmp; tmp="$(mktemp -- "${file}.XXXXXX")" || return 1
	awk -v b="$_pr_begin" -v e="$_pr_end" -v nm="$name" '
		$0 == b { inblk=1; print; next }
		$0 == e { inblk=0; print; next }
		inblk && $0 ~ ("^export " nm "=") { next }
		{ print }' "$file" > "$tmp" && cat -- "$tmp" > "$file"
	rm -f -- "$tmp"
	echo "Removed \$$name from the registry."
}

to() {
	[ $# -ne 1 ] && { echo "Usage: to <name>"; return 1; }
	local name="$1"
	[ -z "${!name+set}" ] && { echo "Error: \$$name is not set (try: pl)."; return 1; }
	local target="${!name}"
	[ ! -d "$target" ] && { echo "Error: \$$name -> '$target' is not a directory."; return 1; }
	builtin cd -- "$target"        # bypass the zoxide cd() wrapper for a deterministic jump
}

_pr_complete() {
	local cur="${COMP_WORDS[COMP_CWORD]}"
	COMPREPLY=( $(compgen -W "$(_pr_names)" -- "$cur") )
}
complete -F _pr_complete to
complete -F _pr_complete prm

# --- artifact registry: dataset / asset / checkpoint over HF (see `art`) ---
# Thin wrappers over the `art` tool (~/dotfiles/bin/art, on PATH). Each namespace
# is one HF repo; `art` reads the nearest .artifacts.yaml up-tree. ls/pull/push.
dsl(){ art ls dataset; }
dspull(){ art pull dataset "$@"; }
dspush(){ art push dataset "$@"; }
asl(){ art ls asset; }
aspull(){ art pull asset "$@"; }
aspush(){ art push asset "$@"; }
ckl(){ art ls checkpoint; }
ckpull(){ art pull checkpoint "$@"; }
ckpush(){ art push checkpoint "$@"; }

# --- run registry: training runs over PSC rsync/ssh (see `run`, sibling of `art`) ---
# Thin wrappers over the `run` tool (~/dotfiles/bin/run, on PATH). One remote (psc) in .runs.yaml.
rls(){ run list psc; }
rpull(){ run pull psc "$@"; }
rpush(){ run push psc "$@"; }
rlocal(){ run local "$@"; }
# seg-model lives in the model project's venv, not on PATH — pin it so it works from anywhere,
# e.g. `seg-model create t40 --from-run $(run path m2f-fullgrid-hpo-v3/t40)`.
seg-model(){ uv run --project ~/repo/refseg-workspace/model seg-model "$@"; }

gpu1() { interact -p GPU-shared --gres=gpu:v100-32:1 -t "${1:-1}:00:00"; }
gpu2() { interact -p GPU-shared --gres=gpu:l40s-48:2 -t "${1:-1}:00:00"; }

# --- fuzzy git commit search (see fgc) ---
# Pickaxe (-G, regex, case-insensitive) prefilters commits whose diff touched
# <pattern>; fzf fuzzy-narrows the oneline candidate list. Enter prints the
# selected hash to stdout for piping (fgc mlflow | xargs git show).
fgc() {
	[ -z "$1" ] && { echo "Usage: fgc <pattern>"; return 1; }
	local pattern="$1"
	git log --all -G"$pattern" -i --color=always \
		--format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \
		| fzf --ansi --no-sort --reverse \
			--preview 'git show --color=always {1}' \
		| grep -oE '[a-f0-9]{7,40}' | head -1
}
