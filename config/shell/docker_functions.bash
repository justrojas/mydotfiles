# Docker helper functions
# - dls: lists active & stopped containers
# - dils: list images
# - dsh <container>: starts a bash/zsh session in a running container
# - dkill <container>: stops a container
# - drm <container>: removes a container
# - dcommit <container> <image:tag>: commit container to new image
# - drunning <container>: checks if a container is running
#
# <container> can be the container ID or name.

#### Color helpers ####
# Deliberately NOT exported. These used to be `export`ed, which pushed eleven
# variables named RED/GREEN/BLUE/YELLOW/NC/... into the environment of every
# child process of an interactive shell — including install scripts, which
# declare their own `readonly RED=...` in lib/common.sh with different values.
# Shell-local is all that's needed; only these four are actually used.
_DF_LYELLOW='\033[1;33m'
_DF_LBLUE='\033[1;34m'
_DF_LGRAY='\033[1;37m'
_DF_NC='\033[0m'

function color_echo {
    echo -e "${1}${2}${_DF_NC}"
}

#### Docker utilities ####

function drunning {
    [[ "$(docker container inspect -f '{{.State.Status}}' "$1" 2>/dev/null)" == "running" ]]
}

function dls {
    color_echo "$_DF_LBLUE" "Active docker containers:"
    docker container ls
    echo ""
    color_echo "$_DF_LYELLOW" "Stopped docker containers:"
    docker ps --filter "status=exited"
}

function dils {
    color_echo "$_DF_LGRAY" "Docker images:"
    docker images
}

function dsh {
    if [[ "$#" -ne 1 ]]; then
        echo "Usage: dsh <container>"
        return 1
    fi
    if ! drunning "$1"; then
        docker restart "$1"
    fi
    local shell
    shell=$(docker exec "$1" sh -c 'command -v zsh || command -v bash' 2>/dev/null || echo "sh")
    docker exec -it "$1" "$shell"
}

function dkill {
    if [[ "$#" -ne 1 ]]; then
        echo "Usage: dkill <container>"
        return 1
    fi
    if drunning "$1"; then
        docker kill "$1"
    else
        echo "Container $1 is not running."
    fi
}

function drm {
    if [[ "$#" -ne 1 ]]; then
        echo "Usage: drm <container>"
        return 1
    fi
    docker rm "$1"
}

function dcommit {
    if [[ "$#" -ne 2 ]]; then
        echo "Usage: dcommit <container> <image:tag>"
        return 1
    fi
    if drunning "$1"; then
        echo "Unable to commit. Container $1 is still running. Stop it first."
        return 1
    fi
    docker commit "$1" "$2"
}
