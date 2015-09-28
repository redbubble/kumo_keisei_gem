#!/bin/bash

set -e

echo "--- :wind_chime: Building gem :wind_chime:"

export  =$BUILDKITE_BUILD_NUMBER

gem build kumo_keisei.gemspec
