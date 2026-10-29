.PHONY: all build build-debug open run test clean help

# Ensure standard Xcode toolchain is used by default to prevent Swift OSS toolchain / Apple SDK mismatch
ifeq ($(origin TOOLCHAINS),environment)
export TOOLCHAINS := default
else
export TOOLCHAINS ?= default
endif

APP_BUNDLE = build/InternalSoundRecorder.app

all: build

help:
	@echo "InternalSoundRecorder — Make Targets:"
	@echo "  make build       - Build universal release binary and package into macOS .app bundle"
	@echo "  make build-debug - Build debug binary with swift build"
	@echo "  make open        - Open the project in Xcode (open Package.swift)"
	@echo "  make run         - Launch the packaged macOS app bundle"
	@echo "  make test        - Run all unit and fault-tolerance integration tests"
	@echo "  make clean       - Clean build artifacts and temporary files"

build:
	@echo "==> Packaging macOS App Bundle..."
	@./Scripts/bundle_app.sh

SWIFT ?= xcrun --toolchain XcodeDefault swift

build-debug:
	@echo "==> Building Debug binary..."
	@$(SWIFT) build

open:
	@echo "==> Opening Package.swift in Xcode..."
	@open Package.swift

run: build
	@echo "==> Launching InternalSoundRecorder.app..."
	@open $(APP_BUNDLE)

test:
	@echo "==> Running test suite..."
	@$(SWIFT) test

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build .build
	@echo "==> Clean complete."
