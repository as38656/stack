SUITE := trixie
OUT := out/$(SUITE)
CACHE ?= $(HOME)/.cache/as38656-stack
BUILDER := as38656-stack-builder:$(SUITE)

COMPONENTS := vpp zebra-rs

.PHONY: all builder $(COMPONENTS) smoke apt-test unit-test lint clean

all: $(COMPONENTS)

builder:
	docker build --build-arg SUITE=$(SUITE) -t $(BUILDER) -f build/builder.Dockerfile build

$(COMPONENTS): builder
	mkdir -p $(OUT) $(CACHE)
	docker run --rm \
		-v $(CURDIR):/stack:ro -v $(CURDIR)/$(OUT):/out -v $(CACHE):/cache \
		-e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) \
		$(BUILDER) /stack/build/$@.sh

# The zebra-rs binary gets file capabilities on install. The kernel refuses to
# run it unless the container may hold them too.
smoke:
	docker run --rm --cap-add NET_ADMIN --cap-add NET_BROADCAST \
		-v $(CURDIR):/stack:ro -v $(CURDIR)/$(OUT):/out:ro \
		-e VPP_COMMIT=$$(scripts/component-commit.sh vpp) \
		-e ZEBRA_RS_COMMIT=$$(scripts/component-commit.sh zebra-rs) \
		debian:$(SUITE) /stack/test/smoke.sh

apt-test:
	docker run --rm -v $(CURDIR):/stack:ro debian:$(SUITE) /stack/test/apt-repo.sh

unit-test:
	python3 -m unittest discover -s aptrepo/tests -t .

lint:
	shellcheck build/*.sh test/*.sh test/fake-gh/gh scripts/*.sh

clean:
	rm -rf out
