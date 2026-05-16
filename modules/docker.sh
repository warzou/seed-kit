#!/bin/sh

module_docker_plan() {
  echo "- check whether docker is installed"
  echo "- install Docker Engine from the official Docker apt repository"
  echo "- install docker CLI, containerd, buildx plugin, and compose plugin"
  echo "- validate with docker --version, docker compose version, and docker service status"
  echo "- no containers, compose files, stacks, secrets, reboot, or user group changes"
}

module_docker_dependencies() {
  echo "requires: debian-like"
  echo "requires: network"
  echo "requires: sudo"
  echo "package-source: official Docker apt repository"
  echo "package: ca-certificates"
  echo "package: curl"
  echo "package: docker-ce"
  echo "package: docker-ce-cli"
  echo "package: containerd.io"
  echo "package: docker-buildx-plugin"
  echo "package: docker-compose-plugin"
  echo "provides: docker"
  echo "provides: docker compose"
  echo "manual: add user to docker group only if explicitly desired"
}
