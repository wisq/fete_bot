TASK ?= deploy

# Run `make <dev/prod> PULL=1` to upgrade docker images to latest.
ifeq ($(PULL),1)
	BUILD_ARGS += --pull
endif

all: test hooks

hooks:
	cd .git/hooks && ln -nsf ../../hooks/* ./

test:
	mix test

# Metatargets:
dev: dev_deploy
prod: prod_deploy

# Dev:
dev_build:
	docker context use default
	$(MAKE) docker_build ENV=dev

dev_deploy: dev_build
	$(MAKE) docker_deploy ENV=dev

# Prod:
prod_build: test
	docker context use ocean
	$(MAKE) docker_build ENV=prod

prod_deploy: prod_build
	$(MAKE) docker_deploy ENV=prod UPFLAGS=--detach

# Common:
docker_build:
	docker build -t fetebot-release $(BUILD_ARGS) --build-arg mix_env=$(ENV) .

docker_deploy:
	ln -nsf .env.$(ENV) .env.deploy
	docker compose up $(UPFLAGS)

.PHONY: hooks test dev prod dev_build dev_deploy prod_build prod_deploy docker_build docker_deploy
