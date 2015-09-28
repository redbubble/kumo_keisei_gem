#!/bin/bash

set -e

echo "--- :wind_chime: Building gem :wind_chime:"

export KUMO_KEISEI_VERSION=$BUILDKITE_BUILD_NUMBER

gem build kumo_keisei.gemspec
