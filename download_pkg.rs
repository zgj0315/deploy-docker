#!/bin/bash

set -e

mkdir -p pkgs/aarch64
curl -SL https://github.com/docker/compose/releases/download/v5.0.2/docker-compose-linux-aarch64 -o pkgs/aarch64/docker-compose-linux-aarch64
curl -SL https://download.docker.com/linux/static/stable/aarch64/docker-29.2.1.tgz -o pkgs/aarch64/docker-29.2.1.tgz
mkdir -p pkgs/x86_64
curl -SL https://github.com/docker/compose/releases/download/v5.0.2/docker-compose-linux-x86_64 -o pkgs/x86_64/docker-compose-linux-x86_64
curl -SL https://download.docker.com/linux/static/stable/x86_64/docker-29.2.1.tgz -o pkgs/x86_64/docker-29.2.1.tgz
