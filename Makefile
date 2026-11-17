.PHONY: help app check check-live package run clean
.DEFAULT_GOAL := help

VERSION ?= 1.0.0
UNIVERSAL ?= 0
ARCH_LABEL := $(if $(filter 1,$(UNIVERSAL)),universal,$(shell uname -m))
ARCHIVE := dist/OrbSweep-$(VERSION)-macOS-$(ARCH_LABEL).zip

help:
	@echo "make app             编译并签名 dist/OrbSweep.app"
	@echo "make run             编译并打开应用"
	@echo "make check           运行安全规则检查（不需要 OrbStack）"
	@echo "make check-live      安全规则检查 + OrbStack 只读扫描"
	@echo "make package         编译并生成 ZIP；支持 VERSION=1.0.0 UNIVERSAL=1"
	@echo "make clean           清理编译缓存与 dist 构建产物"

app:
	APP_VERSION="$(VERSION)" UNIVERSAL="$(UNIVERSAL)" bash scripts/build-app.sh

check:
	swift run SafetyChecks

check-live:
	ORBSWEEP_LIVE_TEST=1 swift run SafetyChecks

package: app
	ditto -c -k --sequesterRsrc --keepParent dist/OrbSweep.app "$(ARCHIVE)"
	unzip -t "$(ARCHIVE)"
	@echo "Packaged: $(ARCHIVE)"

run: app
	open dist/OrbSweep.app

clean:
	swift package clean
	rm -rf dist
