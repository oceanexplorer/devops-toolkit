#!/usr/bin/env bash

eval $(docker-machine env swarm-test-1)

docker network create --driver overlay proxy

docker network create --driver overlay todoapi

curl -o docker-compose-proxy.yml https://raw.githubusercontent.com/vfarcic/docker-flow-proxy/master/docker-compose.yml

export DOCKER_IP=$(docker-machine ip swarm-test-1)

docker-compose -f docker-compose-proxy.yml up -d consul-server

export CONSUL_SERVER_IP=$(docker-machine ip swarm-1)

for i in 2 3; do
    eval $(docker-machine env swarm-test-$i)

    export DOCKER_IP=$(docker-machine ip swarm-test-$i)

    docker-compose -f docker-compose-proxy.yml up -d consul-agent
done

rm docker-compose-proxy.yml

docker service create --name proxy \
    -p 80:80 \
    -p 443:443 \
    -p 8090:8080 \
    --network proxy \
    -e MODE=swarm \
    --replicas 2 \
    -e CONSUL_ADDRESS="$(docker-machine ip swarm-test-1):8500,$(docker-machine ip swarm-test-2):8500,$(docker-machine ip swarm-test-3):8500" \
    --constraint 'node.labels.env == prod-like' \
    vfarcic/docker-flow-proxy

docker service create --name todoapi-db \
    --network todoapi \
    --constraint 'node.labels.env == prod-like' \
    -e POSTGRES_PASSWORD=Testing123 \
    postgres

while true; do
    REPLICAS=$(docker service ls | grep proxy | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep proxy | awk '{print $4}')
    if [[ $REPLICAS == "2/2" || $REPLICAS_NEW == "2/2" ]]; then
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
    --replicas 2 \
    --constraint 'node.labels.env == prod-like' \
    --update-delay 5s \
    oceanexplorer/todoapi:latest

while true; do
    REPLICAS=$(docker service ls | grep oceanexplorer/todoapi | awk '{print $3}')
    REPLICAS_NEW=$(docker service ls | grep oceanexplorer/todoapi | awk '{print $4}')
    if [[ $REPLICAS == "2/2" || $REPLICAS_NEW == "2/2" ]]; then
        break
    else
        echo "Waiting for the todoapi service..."
        sleep 10
    fi
done

curl "$(docker-machine ip swarm-test-1):8090/v1/docker-flow-proxy/reconfigure?serviceName=todoapi&servicePath=/api&port=5050&distribute=true"

echo ""
echo ">> The services are up and running inside the swarm test cluster"
