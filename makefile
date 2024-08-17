# Variables
IMAGE_REPO=guillh
IMAGE_NAME=web3-prometheus-exporter
VERSION=$(version)
APP_PORT=8990
HOST_PORT=8990

# Default target
all: run

# Build and run the Docker image
run:
	docker build -t $(IMAGE_NAME) .
	docker run --rm --name web3-prometheus-exporter -v $(PWD)/docker/example-config.yaml:/app/config.yaml -p $(HOST_PORT):$(APP_PORT) $(IMAGE_NAME)

# Tag and push the Docker image
push: check_version
	docker tag $(IMAGE_NAME) $(IMAGE_REPO)/$(IMAGE_NAME):latest
	docker tag $(IMAGE_NAME) $(IMAGE_REPO)/$(IMAGE_NAME):$(VERSION)
	docker push $(IMAGE_REPO)/$(IMAGE_NAME):latest
	docker push $(IMAGE_REPO)/$(IMAGE_NAME):$(VERSION)

# Check if the version is provided
check_version:
	@if [ -z "$(VERSION)" ]; then echo "VERSION is not set. Use 'make <target> VERSION=<version>'"; exit 1; fi
