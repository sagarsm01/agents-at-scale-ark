#!/usr/bin/env bash

## This script copies the ARK SDK wheel into the build-context directory
## so it can be used as a dependency during Docker build

set -euo pipefail

rm -rf build-context
mkdir -p build-context
cp ../../out/ark-sdk/py-sdk/dist/ark_sdk-*.whl build-context/

# Update pyproject.toml to point to the build-context wheel
sed -i.bak 's|path = "../../out/ark-sdk/py-sdk/dist/ark_sdk-.*\.whl"|path = "./build-context/ark_sdk-$(cat ../../version.txt)-py3-none-any.whl"|' pyproject.toml && \
uv remove ark_sdk || true && \
uv add ./build-context/ark_sdk-$(cat ../../version.txt)-py3-none-any.whl && \
rm -f uv.lock && uv sync

