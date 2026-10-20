# Atajos. `make extract` descarga 1.6 GB y tarda ~10 min.
SHELL := /bin/bash
TAG ?= rubyx-20261015
OUT ?= work/blueprint

.PHONY: help extract check repack clean

help:
	@echo "make extract   extrae el blueprint del release $(TAG)"
	@echo "make check     comprueba configs/ruby_defconfig contra Droidspaces"
	@echo "make repack    reempaqueta work/boot_unpacked en work/boot-new.img"
	@echo "make clean     borra work/ y out/"

extract:
	./scripts/extract-release.sh $(TAG) $(OUT)

check:
	./scripts/check-droidspaces.sh configs/ruby_defconfig || true

repack:
	./scripts/repack-boot.sh work/boot_unpacked work/boot-new.img

clean:
	rm -rf work out out-ack
