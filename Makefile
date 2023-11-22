TASK ?= deploy

# Run `make prod PULL=1` to upgrade docker images to latest.
ifeq ($(PULL),1)
	BUILD_ARGS += --pull
endif

all: test hooks

hooks:
	cd .git/hooks && ln -nsf ../../hooks/* ./

test:
	mix test

prod: test
	fly deploy --build-arg mix_env=prod

.PHONY: hooks test prod
