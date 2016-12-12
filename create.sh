#!/bin/bash

sudo ifconfig vboxnet0 down && sudo ifconfig vboxnet0 up

echo "create vm"

# create machine
docker-machine create \
      --engine-env 'DOCKER_OPTS="-H unix:///var/run/docker.sock"' \
      --driver virtualbox \
leader1
docker-machine create \
      --engine-env 'DOCKER_OPTS="-H unix:///var/run/docker.sock"' \
      --driver virtualbox \
worker1
docker-machine create \
      --engine-env 'DOCKER_OPTS="-H unix:///var/run/docker.sock"' \
      --driver virtualbox \
worker2

ip_leader1=$(docker-machine ip leader1)

echo "initialize swarm"
# create swarm cluster
eval "$(docker-machine env leader1)"
docker swarm init \
    --listen-addr $ip_leader1 \
    --advertise-addr $ip_leader1

token=$(docker swarm join-token worker -q)
echo "token: $token"

eval "$(docker-machine env worker1)"
docker swarm join \
    --token $token \
    $ip_leader1:2377

eval "$(docker-machine env worker2)"
docker swarm join \
    --token $token \
    $ip_leader1:2377


eval "$(docker-machine env leader1)"
echo "Network creation..."
docker network create \
    -d overlay \
    --subnet 10.1.9.0/24 \
    multi-host-net
echo "Network created !"

echo "create consul leader"
docker service create --replicas 1 \
    --name consul-leader \
    --publish 8501:8500 \
    --network multi-host-net \
    --constraint=node.hostname=='leader1' \
    progrium/consul -server -bootstrap-expect 1 -ui-dir /ui

until docker ps --no-trunc | grep 'consul-leader'
do
    echo "wait for container"
    sleep 1
done

eval "$(docker-machine env leader1)"
container_id=$(docker ps --no-trunc | grep 'consul-leader' | cut -d ' ' -f 1)
#echo "container-id: $container_id"
format_string="'.[].Containers.\"$container_id\".IPv4Address'"
format_command="docker network inspect multi-host-net | jq -r $format_string | cut -d '/' -f 1"
#echo "format_string: $format_string"
#echo "format_command: $format_command"
ip_consul_leader=$(eval $format_command)

echo "consul-leader: $ip_consul_leader"

# docker service create --replicas 1 \
#     --name consul-node1 \
#     --network multi-host-net \
#     --constraint 'node.hostname == worker1' \
#     progrium/consul -server -join $ip_consul_leader

# docker service create --replicas 1 \
#     --name consul-node2 \
#     --network multi-host-net \
#     --constraint 'node.hostname == worker2' \
#     progrium/consul -server -join $ip_consul_leader

echo "one consul per swarm node"
docker service create \
    --name consul-nodes \
    --publish 8500:8500 \
    --network multi-host-net \
    --mode global \
    progrium/consul -server -join $ip_consul_leader -ui-dir /ui



# visualizer
echo "add vizualiser"
eval "$(docker-machine env leader1)"
docker service create \
  --name=viz \
  --publish=5050:8080/tcp \
  --constraint=node.role==manager \
  --mount=type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  manomarks/visualizer


echo "add traefik loadbalanceur"
docker service create \
    --name traefik \
    --constraint=node.role==manager \
    --publish 80:80 \
    --publish 8080:8080 \
    --mount type=bind,source=$PWD/traefik.toml,target=/etc/traefik/traefik.toml \
    --network multi-host-net \
    --mode global \
    traefik \
    --consulCatalog.endpoint=consul-nodes.multi-host-net:8500 \
    --consul.endpoint=consul-nodes.multi-host-net:8500 \
    --web


echo "add application"
docker service create --replicas 3 \
    --name web \
    --label traefik.port=80 \
    --label traefik.backend=spring \
    --label traefik.host=testspring.traefik \
    --network multi-host-net \
    --env NETWORK=10.1 \
    --env CONSUL_HOST=consul-nodes.multi-host-net wescale/consuldemo

echo "Go to http://$ip_leader1:5050"
echo "Go to http://$ip_leader1:8080"
echo "Go to http://$ip_leader1:8500"


echo "add one worker and one manager"
docker-machine create \
      --engine-env 'DOCKER_OPTS="-H unix:///var/run/docker.sock"' \
      --driver virtualbox \
leader2
docker-machine create \
      --engine-env 'DOCKER_OPTS="-H unix:///var/run/docker.sock"' \
      --driver virtualbox \
worker3

eval "$(docker-machine env worker3)"
docker swarm join \
    --token $token \
    $ip_leader1:2377

eval "$(docker-machine env leader1)"
token_leader=$(docker swarm join-token manager -q)
echo "token_leader: $token_leader"

eval "$(docker-machine env leader2)"
docker swarm join \
    --token $token_leader \
    $ip_leader1:2377

echo "web scale to 10"
docker service scale web=10