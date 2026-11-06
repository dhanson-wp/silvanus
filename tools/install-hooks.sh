#!/bin/bash
# Points git at the tracked hooks in .githooks.
cd "$(dirname "$0")/.." && git config core.hooksPath .githooks
