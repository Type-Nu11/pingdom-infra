RUST_TARGET_DIR := target/release
RUST_LIB := $(RUST_TARGET_DIR)/libapp_validator.so

ZIG_DIR := zig/guard
ZIG_LIB := $(ZIG_DIR)/zig-out/lib/libweb_guard.so

.PHONY: check build-rust build-zig build-native docker-build up down clean

check:
	cargo check

build-rust:
	cargo build --release

build-zig:
	cd $(ZIG_DIR) && zig build -Doptimize=ReleaseFast

build-native: build-rust build-zig
	@echo "Native libraries built"

docker-build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

clean:
	cargo clean
	rm -rf $(ZIG_DIR)/zig-out