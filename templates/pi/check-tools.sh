#!/usr/bin/env bash
# Offline compatibility smoke; no Compose .env, credentials or host mounts.
set -euo pipefail
if [[ $# -gt 1 || ${1:-} == -* ]]; then
    echo "Usage: $0 [image]" >&2
    exit 2
fi
image="${1:-sannux/pi:latest}"
docker run --rm -i --pull=never --network none --read-only \
    --tmpfs /home/agent:mode=1777 --tmpfs /tmp:exec,mode=1777 \
    --workdir /tmp --entrypoint /bin/bash "$image" -s <<'SH'
set -euo pipefail
test "$(id -u)" -ne 0
test -z "$(ls -A "$HOME")"
for tool in node npm rtk pi codex; do
    command -v "$tool"
    timeout 30 "$tool" --version
done
test "$(timeout 30 rtk proxy printf 'proxy-ok')" = proxy-ok
timeout 30 rtk git --help >/dev/null
timeout 30 pi --help > /tmp/pi-help
for flag in --print --no-session --tools; do grep -q -- "$flag" /tmp/pi-help; done
timeout 30 codex exec --help > /tmp/codex-help
for flag in --ephemeral --json --dangerously-bypass-approvals-and-sandbox; do
    grep -q -- "$flag" /tmp/codex-help
done
timeout 30 codex app-server --help > /tmp/app-server-help
grep -q -- --listen /tmp/app-server-help
# Check the catalog command interface only: never query models/accounts.
timeout 30 codex debug --help > /tmp/codex-debug-help
grep -q models /tmp/codex-debug-help
export NPM_ROOT="$(timeout 30 npm root -g)"
timeout 60 node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const root = process.env.NPM_ROOT;
const require = createRequire(`${root}/npm/package.json`);
const semver = require('semver');
for (const name of ['npm', '@earendil-works/pi-coding-agent', '@openai/codex']) {
    const pkg = JSON.parse(fs.readFileSync(`${root}/${name}/package.json`, 'utf8'));
    if (pkg.engines?.node) {
        assert(semver.satisfies(process.version, pkg.engines.node), `${name}: ${pkg.engines.node}`);
    }
}
// Exercise Pi's public TypeScript extension loader, not a private dependency.
// Help includes registered extension flags and exits without a model request.
fs.writeFileSync('/tmp/sannux-pi-smoke.ts', `
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
export default function (pi: ExtensionAPI): void {
    const answer: number = 42;
    pi.registerFlag('sannux-smoke', {
        type: 'boolean',
        description: 'Sannux TypeScript extension: ' + answer,
    });
}
`);
const { stdout: extensionHelp } = await promisify(execFile)('pi', [
    '--offline', '--no-extensions', '--extension', '/tmp/sannux-pi-smoke.ts', '--help',
], { timeout: 30000, maxBuffer: 100000 });
// Pi can exit successfully even when an extension failed to load.
assert.match(extensionHelp, /^\s+--sannux-smoke\s+Sannux TypeScript extension: 42\s*$/m,
    'Pi help must include the flag registered by the TypeScript fixture');
// Actual Debian Chromium + floating playwright-core + browser-fetch integration.
// The fixture is in-container loopback only; the container has no external network.
const server = createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html');
    response.end('<title>Smoke fixture</title><p>' + 'Readable local fixture text. '.repeat(12) +
        '</p><a href="/next">Next</a><script>document.body.dataset.rendered="yes";' +
        'document.body.append(" JavaScript rendered successfully.")</script>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
    const url = `http://127.0.0.1:${server.address().port}/`;
    const { stdout } = await promisify(execFile)('browser-fetch', [url], {
        timeout: 45000, maxBuffer: 100000,
        env: { ...process.env, BROWSER_FETCH_RENDER_WAIT_MS: '0' },
    });
    const result = JSON.parse(stdout);
    assert.equal(result.ok, true, stdout);
    assert.equal(result.title, 'Smoke fixture');
    assert(result.text.includes('JavaScript rendered successfully.'));
    assert(result.links.some(link => link.url === `${url}next`));
} finally {
    await new Promise(resolve => server.close(resolve));
}
console.log('Node engines, CLI interfaces, Pi TypeScript extension and rendered browser-fetch fixture passed');
JS
SH
