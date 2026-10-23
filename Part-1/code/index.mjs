import crypto from 'node:crypto';
import { getConfig as defaultGetConfig } from './config.mjs';

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});

/** Constant-time comparison so the key cannot be guessed byte by byte. */
const keysMatch = (presented, expected) => {
  if (typeof presented !== 'string' || typeof expected !== 'string') return false;
  const a = Buffer.from(presented);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
};

/**
 * Factory so tests can inject a configuration source.
 *
 * @param getConfig        async () => config map from Parameter Store
 * @param requireApiKey    enforce x-api-key against config['api-key']
 */
export const makeHandler = (
  getConfig = defaultGetConfig,
  requireApiKey = process.env.REQUIRE_API_KEY === 'true',
) =>
  async (event, context) => {
    const requestId = context?.awsRequestId;
    console.log('issuing asset id', { requestId, path: event?.rawPath });

    let config;
    try {
      config = await getConfig();
    } catch (err) {
      // Fail closed: without configuration we cannot promise a validity window.
      console.error('configuration unavailable', { requestId, error: err.message });
      return json(503, { error: 'configuration unavailable', requestId });
    }

    if (requireApiKey) {
      const presented = event?.headers?.['x-api-key'];
      if (!keysMatch(presented, config['api-key'])) {
        console.warn('rejected request: bad or missing api key', { requestId });
        return json(401, { error: 'unauthorized', requestId });
      }
    }

    const responseValidPeriod = Number(config['response-valid-period-ms']);
    const assetID = crypto.randomUUID();

    return json(200, {
      assetID,
      validUntil: Date.now() + responseValidPeriod,
    });
  };

export const handler = makeHandler();
