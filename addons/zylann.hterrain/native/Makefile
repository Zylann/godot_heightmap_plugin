TARGET_LINUX?=x86_64-unknown-linux-gnu
TARGET_OSX?=x86_64-apple-darwin
TARGET_WIN64?=x86_64-pc-windows-gnu


build-rust-all: build-rust-linux build-rust-win64 build-rust-osx


build-rust-linux:
	cargo build --manifest-path=rust-src/Cargo.toml --release --target $(TARGET_LINUX)
	cp rust-src/target/$(TARGET_LINUX)/release/libhterrain.so bin/linux/libhterrain_rust.so
	strip bin/linux/libhterrain_rust.so


build-rust-osx:
	cargo build --manifest-path=rust-src/Cargo.toml --release --target $(TARGET_OSX)
	cp rust-src/target/$(TARGET_OSX)/release/libhterrain.dylib bin/osx/libhterrain_rust.dylib


build-rust-win64:
	cargo build --manifest-path=rust-src/Cargo.toml --release --target $(TARGET_WIN64)
	cp rust-src/target/$(TARGET_WIN64)/release/hterrain.dll bin/win64/hterrain_rust.dll
	strip bin/win64/hterrain_rust.dll

