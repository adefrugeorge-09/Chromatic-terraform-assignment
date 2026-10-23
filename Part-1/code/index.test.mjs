import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeHandler } from './index.mjs';
import { createConfigLoader, DEFAULTS } from './config.mjs';

const ctx = { awsRequestId: 'req-1' };

test('returns an asset id valid for the configured period', async () => {
  const handler = makeHandler(async () => ({ 'response-valid-period-ms': '1000' }));
  const before = Date.now();

  const res = await handler({ rawPath: '/' }, ctx);

  assert.equal(res.statusCode, 200);
  assert.equal(res.headers['content-type'], 'application/json');
  const body = JSON.parse(res.body);
  assert.match(body.assetID, /^[0-9a-f-]{36}$/);
  assert.ok(body.validUntil >= before + 1000);
  assert.ok(body.validUntil <= Date.now() + 1000);
});

test('fails closed with 503 when configuration cannot be loaded', async () => {
  const handler = makeHandler(async () => {
    throw new Error('ssm down');
  });

  const res = await handler({}, ctx);

  assert.equal(res.statusCode, 503);
  assert.equal(JSON.parse(res.body).requestId, 'req-1');
});

test('enforces the api key when required', async () => {
  const handler = makeHandler(async () => ({ 'api-key': 'correct-horse' }), true);

  const missing = await handler({ headers: {} }, ctx);
  assert.equal(missing.statusCode, 401);

  const wrong = await handler({ headers: { 'x-api-key': 'wrong' } }, ctx);
  assert.equal(wrong.statusCode, 401);

  const right = await handler({ headers: { 'x-api-key': 'correct-horse' } }, ctx);
  assert.equal(right.statusCode, 200);
});

test('skips the api key check when not required (local dev)', async () => {
  const handler = makeHandler(async () => ({}), false);
  const res = await handler({ headers: {} }, ctx);
  assert.equal(res.statusCode, 200);
});

test('config loader caches, overlays defaults and serves stale on refresh failure', async () => {
  let calls = 0;
  const getConfig = createConfigLoader({
    path: '/important-api/test',
    ttlMs: 0, // expire immediately so every call attempts a refresh
    fetch: async () => {
      calls += 1;
      if (calls > 1) throw new Error('ssm down');
      return { 'api-key': 'secret' };
    },
  });

  const first = await getConfig();
  assert.equal(first['api-key'], 'secret');
  assert.equal(first['response-valid-period-ms'], DEFAULTS['response-valid-period-ms']);

  const second = await getConfig(); // refresh fails -> stale values returned
  assert.deepEqual(second, first);
  assert.equal(calls, 2);
});

test('config loader refuses to run without a parameter path', async () => {
  const getConfig = createConfigLoader({ path: undefined, ttlMs: 1000 });
  await assert.rejects(getConfig, /CONFIG_PARAMETER_PATH/);
});
