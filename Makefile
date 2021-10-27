.PHONY: help all create delete deploy check clean test load-test flux caddy code-server

help :
	@echo "Usage:"
	@echo "   make all              - create a cluster and deploy the apps"
	@echo "   make create           - create a k3d cluster"
	@echo "   make delete           - delete the k3d cluster"
	@echo "   make deploy           - deploy the apps to the cluster"
	@echo "   make check            - check the endpoints with curl"
	@echo "   make test             - run a WebValidate test"
	@echo "   make load-test        - run a 60 second WebValidate test"
	@echo "   make clean            - delete the apps from the cluster"

all : create deploy flux

delete :
	# delete the cluster (if exists)
	@# this will fail harmlessly if the cluster does not exist
	@k3d cluster delete

create : delete
	@# create the cluster and wait for ready
	@# this will fail harmlessly if the cluster exists
	@# default cluster name is k3d

	@k3d cluster create --registry-use k3d-registry.localhost:5500 --config deploy/k3d.yaml --k3s-server-arg "--no-deploy=traefik" --k3s-server-arg "--no-deploy=servicelb"

	# wait for cluster to be ready
	@kubectl wait node --for condition=ready --all --timeout=60s
	@sleep 20
	@kubectl wait pod -A --all --for condition=ready --timeout=60s

deploy :
	@# continue on most errors

	# deploy prometheus and grafana
	@kubectl apply -f deploy/prometheus
	@kubectl apply -f deploy/grafana

	# deploy fluent bit
	@kubectl apply -f deploy/fluentbit

	# start a jumpbox pod
	@kubectl run jumpbox --image=ghcr.io/cse-labs/jumpbox --restart=Always

	# wait for the pods to start
	@kubectl wait pod -n monitoring --for condition=ready --all --timeout=30s
	@kubectl wait pod -n logging    --for condition=ready --all --timeout=30s
	@kubectl wait pod jumpbox --for condition=ready --timeout=30s

	# display pod status
	@kubectl get po -A

check :
	# curl all of the endpoints
	@curl localhost:30000
	@curl localhost:32000

	# check jumpbox
	@kubectl exec -it jumpbox -- pwd

clean :
	# delete the deployment
	@# continue on error
	-kubectl delete pod jumpbox --ignore-not-found=true
	-kubectl delete ns monitoring --ignore-not-found=true
	-kubectl delete ns logging --ignore-not-found=true

	# show running pods
	@kubectl get po -A

test :
	# use WebValidate to run a test
	cd webv && webv --verbose --summary tsv --server http://localhost:30080 --files baseline.json baseline.json baseline.json
	# the 400 and 404 results are expected
	# Errors and ValidationErrorCount should both be 0

load-test :
	# use WebValidate to run a 60 second test
	cd webv && webv --verbose --server http://localhost:30080 --files benchmark.json --run-loop --sleep 100 --duration 60

flux :
	@./flux-bootstrap

caddy :
	# install caddy
	sudo apt update
	sudo apt upgrade -y
	sudo apt-get install -y caddy
	sudo systemctl status caddy

code-server :
	# install code-server
	~/cs-install.sh --version 3.10.2
	# rm ~/cs-install.sh
	sudo systemctl enable --now code-server@${USER}
