.PHONY: all build build-debug run test clean help

APP_BUNDLE = build/InternalSoundRecorder.app

all: build

help:
	@echo "InternalSoundRecorder — Make Targets:"
	@echo "  make build       - Build release binary and package into macOS .app bundle"
	@echo "  make build-debug - Build debug binary with swift build"
	@echo "  make run         - Launch the packaged macOS app bundle"
	@echo "  make test        - Run all unit and fault-tolerance integration tests"
	@echo "  make clean       - Clean build artifacts and temporary files"

build:
	@echo "==> Packaging macOS App Bundle..."
	@./Scripts/bundle_app.sh

build-debug:
	@echo "==> Building Debug binary..."
	@swift build

run: build
	@echo "==> Launching InternalSoundRecorder.app..."
	@open $(APP_BUNDLE)

test:
	@echo "==> Running test suite..."
	@swift test

clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf build .build
	@echo "==> Clean complete."
