#!/bin/bash -e
FEEDBIN_NAME=docker.io/feedreader/feedbin
NAME=docker.io/feedreader/fedora-feedreader-devel

sudo docker build -f Dockerfile.Feedbin . -t "$FEEDBIN_NAME"
sudo docker push "$FEEDBIN_NAME"

sudo docker build . -t "$NAME"
sudo docker push "$NAME"
