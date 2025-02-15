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
    if [ "$#" -ne 1 ]; then
	echo "Usage: drun <image>" 
	echo "This is a function that runs an image and mounts the working directory to /home/ws in the container"
	return 1
    fi
    local image="$1"

    local current_dir=$(pwd)

    docker run --rm -it --gpus all -v "$current_dir:/home/ws" "$image"
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
}
gs() {
git status
}

ga() {
	git rm -r --cached -f .
	git add .
}

gc() {
	if [ -z "$1" ]; then
		echo "Error: Commit message is required." >&2
		return 1
	fi
	git commit -m "$1"
}

gp() {
	 branch=$(git symbolic-ref --short HEAD)
	 remote=$(git config branch."$branch".remote || echo "origin")
	 echo "Pushing to $remote/$branch..."
	 git push "$remote" "$branch"
}
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
