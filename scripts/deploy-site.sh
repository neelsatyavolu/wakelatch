#!/bin/bash
# Deploys site/ to wakelatch.n3el.dev (Vercel project "wakelatch", no git link).
set -euo pipefail
cd "$(dirname "$0")/../site"
[[ -f .vercel/project.json ]] || vercel link --yes --project wakelatch
vercel deploy --prod --yes
