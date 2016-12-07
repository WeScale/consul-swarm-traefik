#!/bin/bash

eval "$(docker-machine env leader1)"
docker service rm web
# docker rmi itwars/h2o itwars/varnish itwars/haproxy itwars/phpfpm

eval "$(docker-machine env worker2)"
docker swarm leave
eval "$(docker-machine env worker1)"
docker swarm leave
eval "$(docker-machine env leader1)"
docker swarm leave --force

docker-machine rm worker2 --force
docker-machine rm worker1 --force
docker-machine rm leader1 --force

# docker-machine rm consulhost --force

