#!/bin/bash
# Rebuilds foliate-bundle.js from foliate-host.js using esbuild.
# Run from the JS directory: cd vreader/Services/Foliate/JS && ./build-bundle.sh

set -euo pipefail
cd "$(dirname "$0")"

# Create stubs for unsupported formats
echo 'export const makeComicBook = () => { throw new Error("not supported") }' > comic-book.js
echo 'export const makeFB2 = () => { throw new Error("not supported") }' > fb2.js  
echo 'export const makePDF = () => { throw new Error("not supported") }' > pdf.js

# Bundle
npx esbuild foliate-host.js --bundle --format=iife --global-name=FoliateHost --outfile=foliate-bundle.js

# Cleanup stubs
rm -f comic-book.js fb2.js pdf.js

echo "Built foliate-bundle.js ($(wc -c < foliate-bundle.js | tr -d ' ') bytes)"
