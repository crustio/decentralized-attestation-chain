# Build crust env image
FROM rust:latest

ARG TOOLCHAIN
ENV RUSTUP_TOOLCHAIN ${TOOLCHAIN:-nightly-2022-06-01}
RUN apt-get update
RUN apt-get -y install lsb-release wget software-properties-common clang ca-certificates
RUN rustup toolchain install ${RUSTUP_TOOLCHAIN}
RUN rustup update stable
RUN rustup target add wasm32-unknown-unknown --toolchain ${RUSTUP_TOOLCHAIN}
RUN rustup default ${RUSTUP_TOOLCHAIN}
RUN rustc -vV