#!/bin/zsh

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
        echo "Downloads a Google Drive folder, preserving its name"
        echo "Default dest: current directory"
        return 1
    fi

    local url="$1"
    local dest="${2:-.}"

    local folder_id
    folder_id=$(_extract_drive_id "$url")
    if [[ -z "$folder_id" ]]; then
        echo "ERROR: Could not extract folder ID from URL"
        return 1
    fi

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
function cd () {
  builtin cd "$@" || return $?
  [[ -n "$_CD_SOURCING" ]] && return 0
  local _CD_SOURCING=1
  local accumulator="" remaining="${PWD#/}"
  while [[ -n "$remaining" ]]; do
    if [[ "$remaining" == */* ]]; then
      accumulator+="/${remaining%%/*}"
      remaining="${remaining#*/}"
    else
      accumulator+="/$remaining"
      remaining=""
    fi
    if [[ -f "$accumulator/.aliases" ]]; then
      echo "Sourcing $accumulator/.aliases:"
      cat "$accumulator/.aliases"
      source "$accumulator/.aliases"
    fi
  done
  return 0
}

gitdel() {
    git branch -D $1
    git branch -rd origin/$1 2>/dev/null
}

pydb() {
	python3 -m pdb $1
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
