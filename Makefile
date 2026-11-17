SUITE := trixie
OUT := out/$(SUITE)
CACHE ?= $(HOME)/.cache/as38656-stack
BUILDER := as38656-stack-builder:$(SUITE)

COMPONENTS := vpp vpp-etherip

.PHONY: all builder $(COMPONENTS) smoke apt-test unit-test lint clean

# vpp-etherip builds against the packages in $(OUT)/vpp, so vpp goes first.
all:
	$(MAKE) vpp
	$(MAKE) vpp-etherip

builder:
	docker build --build-arg SUITE=$(SUITE) -t $(BUILDER) -f build/builder.Dockerfile build

$(COMPONENTS): builder
	mkdir -p $(OUT) $(CACHE)
	docker run --rm \
		-v $(CURDIR):/stack:ro -v $(CURDIR)/$(OUT):/out -v $(CACHE):/cache \
		-e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) \
		$(BUILDER) /stack/build/$@.sh

smoke:
	docker run --rm \
		-v $(CURDIR):/stack:ro -v $(CURDIR)/$(OUT):/out:ro \
		-e VPP_COMMIT=$$(scripts/component-commit.sh vpp) \
		-e VPP_ETHERIP_COMMIT=$$(scripts/component-commit.sh vpp-etherip) \
		debian:$(SUITE) /stack/test/smoke.sh

apt-test:
	docker run --rm -v $(CURDIR):/stack:ro debian:$(SUITE) /stack/test/apt-repo.sh

unit-test:
	python3 -m unittest discover -s aptrepo/tests -t .

lint:
	shellcheck build/*.sh test/*.sh test/fake-gh/gh scripts/*.sh

clean:
	rm -rf out
