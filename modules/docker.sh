#!/bin/sh

module_docker_plan() {
  echo "- check whether docker is installed"
  echo "- install Docker Engine from the official Docker apt repository"
  echo "- install docker CLI, containerd, buildx plugin, and compose plugin"
  echo "- validate with docker --version, docker compose version, and docker service status"
  echo "- no containers, compose files, stacks, secrets, reboot, or user group changes"
}
