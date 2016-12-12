#!/bin/bash

eval "$(docker-machine env leader1)"
docker service rm web
docker service rm traefik
docker service rm viz
docker service rm consul-leader
docker service rm consul-nodes

eval "$(docker-machine env worker3)"
docker swarm leave
eval "$(docker-machine env worker2)"
docker swarm leave
eval "$(docker-machine env worker1)"
docker swarm leave
eval "$(docker-machine env leader2)"
docker swarm leave --force
eval "$(docker-machine env leader1)"
docker swarm leave --force

docker-machine rm worker3 --force
docker-machine rm worker2 --force
docker-machine rm worker1 --force
docker-machine rm leader2 --force
docker-machine rm leader1 --force

# docker-machine rm consulhost --force

