#!/usr/bin/env bash

docker service rm proxy todoapi todoapi-db

for i in 1 2 3; do
    eval $(docker-machine env swarm-test-$i)

    docker rm consul -f
done

docker network rm proxy todoapi