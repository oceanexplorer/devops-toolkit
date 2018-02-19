#!/usr/bin/env bash

eval $(docker-machine env swarm-1)

docker service create --name registry \
    -p 5000:5000 \
    --reserve-memory 100m \
    --mount "type=bind,source=$PWD,target=/var/lib/registry" \
    registry:2.5.0

docker network create --driver overlay proxy

docker network create --driver overlay todoapi

curl -o docker-compose-proxy.yml https://raw.githubusercontent.com/vfarcic/docker-flow-proxy/master/docker-compose.yml

export DOCKER_IP=$(docker-machine ip swarm-1)

docker-compose -f docker-compose-proxy.yml up -d consul-server

export CONSUL_SERVER_IP=$(docker-machine ip swarm-1)

for i in 2 3; do
    eval $(docker-machine env swarm-$i)

    export DOCKER_IP=$(docker-machine ip swarm-$i)

    docker-compose -f docker-compose-proxy.yml up -d consul-agent
done

rm docker-compose-proxy.yml

docker service create --name proxy \
    -p 80:80 \
    -p 443:443 \
    -p 8090:8080 \
    --network proxy \
    -e MODE=swarm \
    --replicas 3 \
    -e CONSUL_ADDRESS="$(docker-machine ip swarm-1):8500,$(docker-machine ip swarm-2):8500,$(docker-machine ip swarm-3):8500" \
    --reserve-memory 50m \
    vfarcic/docker-flow-proxy

docker service create --name todoapi-db \
    --network todoapi \
    --reserve-memory 150m \
    -e POSTGRES_PASSWORD=Testing123 \
    postgres

while true; do
    REPLICAS=$(docker service ls | grep proxy | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep proxy | awk '{print $4}')
    if [[ $REPLICAS == "3/3" || $REPLICAS_NEW == "3/3" ]]; then
        break
    else
        echo "Waiting for the proxy service..."
        sleep 10
    fi
done

while true; do
    REPLICAS=$(docker service ls | grep todoapi-db | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep todoapi-db | awk '{print $4}')
    if [[ $REPLICAS == "1/1" || $REPLICAS_NEW == "1/1" ]]; then
        break
    else
        echo "Waiting for the todoapi-db service..."
        sleep 10
    fi
done

docker service create --name todoapi \
    -e DATABASE_HOST=todoapi-db \
    -e DATABASE_SA_PASSWORD=Testing123 \
    --network todoapi \
    --network proxy \
    --replicas 3 \
    --reserve-memory 50m \
    --update-delay 5s \
    oceanexplorer/todoapi:latest

while true; do
    REPLICAS=$(docker service ls | grep oceanexplorer/todoapi | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep oceanexplorer/todoapi | awk '{print $4}')
    if [[ $REPLICAS == "3/3" || $REPLICAS_NEW == "3/3" ]]; then
        break
    else
        echo "Waiting for the todoapi service..."
        sleep 10
    fi
done

curl "$(docker-machine ip swarm-1):8090/v1/docker-flow-proxy/reconfigure?serviceName=todoapi&servicePath=/api&port=5050&distribute=true"

echo ""
echo ">> The services are up and running inside the swarm cluster"
