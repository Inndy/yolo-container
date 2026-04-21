all: run

docker-img-ready: default.conf
	docker build -t llm-gateway .
	touch docker-img-ready

default.conf:
	test -f default.conf || { echo Run \"cp defualt.conf.example defualt.conf\" and put your KEY; exit 1; }

yolo-container-net:
	docker network inspect -f OK yolo-container-net || docker network create yolo-container-net

run: docker-img-ready yolo-container-net
	-docker kill llm-gateway
	-docker rm llm-gateway
	# export ANTHROPIC_BASE_URL=http://127.0.0.1:33380/claude/ on docker host
	# export ANTHROPIC_BASE_URL=http://llm-gateway/claude/ in other docker container (must --network yolo-container-net)
	docker run --name llm-gateway --network yolo-container-net -p 127.0.0.1:33380:80 -d --restart unless-stopped llm-gateway

.PHONY: all run
