#!/bin/bash

# Containers to build
image="ollama/ollama"
port="11434"

# There could be other arguments passed to the script, so we need to check all arguments
for arg in "$@"; do
    case $arg in
    # Check argument -p= or --path=, use $path:/root/.ollama, else $path = ollama
    -p=* | --path=*)
        path="${arg#*=}"
        shift
        ;;

    -u | --update-models)
        update_models="true"
        shift
        ;;

    esac
done

# If path is not set, use ollama
if [ -z "$path" ]; then
    path="ollama"
fi

# Volume = $path:/root/.ollama
volume="$path:/root/.ollama"
echo "Volume: $volume"

# Update models
# https://github.com/ollama/ollama/issues/2633#issuecomment-1957315877
cmd_update_models="ollama list | awk 'NR>1 {print \$1}' | xargs -I {} sh -c 'echo \"Updating model: {}\"; ollama pull {}; echo \"--\"' && echo \"All models updated.\""

# Build containers list, "ollama-gpu1" "ollama-gpu2" "ollama-cpu1" "ollama-cpu2"
# Over 24gb of GPU memory, run 2 GPU containers
if nvidia-smi &>/dev/null; then
    echo "NVIDIA GPU found"
    gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits)
    echo "GPU Name: $gpu_name"

    if [ $gpu_memory -gt 24000 ]; then
        echo "GPU Memory over 24GB"
        containers="ollama-gpu1 ollama-gpu2"
    else
        echo "GPU Memory under 24GB"
        containers="ollama-gpu1"
    fi
else
    echo "NVIDIA GPU not found"
fi

# Over 16gb of CPU memory, run 2 CPU containers
cpu_memory=$(free -m | awk '/^Mem:/{print $2}')
if [ $cpu_memory -gt 32000 ]; then
    echo "CPU Memory over 32GB"
    containers="$containers ollama-cpu1 ollama-cpu2"
else
    echo "CPU Memory under 32GB"
    containers="$containers ollama-cpu1"
fi

# Pull the latest ollama image
echo "Pulling the latest ollama image"
sudo docker pull $image

# Remove all ollama containers
running=$(sudo docker ps -a -q --filter ancestor=ollama/ollama)
if [ -z "$running" ]; then
    echo "No containers found"

    for container in $containers; do
        sudo docker stop $container
        sudo docker rm $container
    done
else
    echo "Removing all containers"
    sudo docker stop $(sudo docker ps -a -q --filter ancestor=ollama/ollama)
    sudo docker rm $(sudo docker ps -a -q --filter ancestor=ollama/ollama)
fi

# Run all containers, increase port by 1 for each container
for container in $containers; do
    echo "Running container: $container"
    # If GPU container, add --gpus all
    if [[ $container == *"gpu"* ]]; then
        sudo docker run -d --gpus=all -v $volume -p $port:11434 --name $container $image
    else
        sudo docker run -d -v $volume -p $port:11434 --name $container $image
    fi
    port=$((port + 1))
done

# Update all containers to restart always
echo "Update all containers to restart always"
sudo docker update --restart always $(sudo docker ps -a -q --filter ancestor=ollama/ollama)

# Search for all running containers, if all running, print success message
containers=$(sudo docker ps -a -q --filter ancestor=ollama/ollama)
if [ -z "$containers" ]; then
    echo "No containers found"
else
    echo "All containers are running"
fi

# Print all running containers, limit output of ps to id, name, created, ports
sudo docker ps --format "table {{.ID}}\t{{.Names}}\t{{.CreatedAt}}\t{{.Ports}}" --filter ancestor=ollama/ollama

# Update models
# Check script arguments for --update-models
if [ "$update_models" = "true" ]; then
    echo "Updating models"
    sudo docker exec -it $container sh -c "$cmd_update_models"
fi

# List model information from last container
echo "Listing models on last container"
sudo docker exec -it $container ollama list

# We're done
echo "All done ✔︎"
