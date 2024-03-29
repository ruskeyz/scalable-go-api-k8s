# Check to see if we can use ash, in Alpine images, or default to BASH.
SHELL_PATH = /bin/ash
SHELL = $(if $(wildcard $(SHELL_PATH)),/bin/ash,/bin/bash)

run:
	go run app/services/sales-api/main.go | go run app/tooling/logfmt/main.go -service=$(SERVICE_NAME)

run-help:
	go run app/services/sales-api/main.go --help

tidy:
	go mod tidy
	go mod vendor

# Deploy First Mentality
# ==============================================================================
#   $ sudo rm -rf /Library/Developer/CommandLineTools
#   $ sudo xcode-select --install
#   Then it installed with brew (arm64)
# ==============================================================================
# Install Tooling and Dependencies
#
#	If you are running a mac machine with brew, run these commands:
#	$ make dev-brew  or  make dev-brew-arm64
#	$ make dev-docker
#	$ make dev-gotooling
#
#	If you are running a linux machine with brew, run these commands:
#	$ make dev-brew-common
#	$ make dev-docker
#	$ make dev-gotooling
#   Follow instructions to install Telepresence online
#
#	If you are a windows user with brew, run these commands:
#	$ make dev-brew-common
#	$ make dev-docker
#	$ make dev-gotooling
#   Follow instructions to install Telepresence online

# ==============================================================================
# ==============================================================================
# Starting The Project
#
#	If you want to use telepresence (recommended):
#	$ make dev-up
#	$ make dev-update-apply
#
#	Note: If you attempted to run with telepresence and it didn't work, you may
#		  want to restart the cluster.
# ==============================================================================
# ==============================================================================
# Define dependencies
GOLANG          := golang:1.21
ALPINE          := alpine:3.18
KIND            := kindest/node:v1.27.3
TELEPRESENCE    := datawire/ambassador-telepresence-manager:2.14.2

KIND_CLUSTER    := api-starter-cluster
NAMESPACE       := sales-system
APP             := sales
BASE_IMAGE_NAME := api-starter/service
SERVICE_NAME    := sales-api
VERSION         := 0.0.1
SERVICE_IMAGE   := $(BASE_IMAGE_NAME)/$(SERVICE_NAME):$(VERSION)
METRICS_IMAGE   := $(BASE_IMAGE_NAME)/$(SERVICE_NAME)-metrics:$(VERSION)
# ==============================================================================
# Running from within k8s/kind
# Install dependencies

dev-gotooling:
	go install github.com/divan/expvarmon@latest
	go install github.com/rakyll/hey@latest
	go install honnef.co/go/tools/cmd/staticcheck@latest
	go install golang.org/x/vuln/cmd/govulncheck@latest
	go install golang.org/x/tools/cmd/goimports@latest

dev-brew-common:
	brew update
	brew tap hashicorp/tap
	brew list kind || brew install kind
	brew list kubectl || brew install kubectl
	brew list kustomize || brew install kustomize
	brew list pgcli || brew install pgcli
	brew list vault || brew install vault

dev-brew: dev-brew-common
	brew list datawire/blackbird/telepresence || brew install datawire/blackbird/telepresence

dev-brew-arm64: dev-brew-common
	brew list datawire/blackbird/telepresence-arm64 || brew install datawire/blackbird/telepresence-arm64

dev-docker:
	docker pull $(GOLANG)
	docker pull $(ALPINE)
	docker pull $(KIND)
	docker pull $(TELEPRESENCE)

# Building containers
all: service

service:
	docker build \
		-f zarf/docker/dockerfile.service \
		-t $(SERVICE_IMAGE) \
		--build-arg BUILD_REF=$(VERSION) \
		--build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
		.

dev-up:
	kind create cluster \
		--image $(KIND) \
		--name $(KIND_CLUSTER) \
		--config zarf/k8s/dev/kind-config.yaml

	kubectl wait --timeout=120s --namespace=local-path-storage --for=condition=Available deployment/local-path-provisioner

dev-down:
	kind delete cluster --name $(KIND_CLUSTER)

dev-load:
	kind load docker-image $(SERVICE_IMAGE) --name $(KIND_CLUSTER)

dev-apply:
	kustomize build zarf/k8s/dev/sales | kubectl apply -f -
	kubectl wait pods --namespace=$(NAMESPACE) --selector app=$(APP) --timeout=120s --for=condition=Ready

dev-restart:
	kubectl rollout restart deployment $(APP) --namespace=$(NAMESPACE)

dev-update: all dev-load dev-restart

dev-update-apply: all dev-load dev-apply

# ------------------------------------------------------------------------------

dev-logs:
	kubectl logs --namespace=$(NAMESPACE) -l app=$(APP) --all-containers=true -f --tail=100 --max-log-requests=6 | go run app/tooling/logfmt/main.go -service=$(SERVICE_NAME)

dev-status:
	kubectl get nodes -o wide
	kubectl get svc -o wide
	kubectl get pods -o wide --watch --all-namespaces

dev-describe-sales:
	kubectl describe pod --namespace=$(NAMESPACE) -l app=$(APP)
