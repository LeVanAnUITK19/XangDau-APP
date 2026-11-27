# API contract

Base prefix: `/api/v1`. Success responses use `{ success: true, data, meta }`; errors use `{ success: false, error: { code, message } }`.

The current provider reads `GET /api/fuel-prices/petrolimex` from [VietFuelAPI](https://github.com/TranQui004/vietfuel-api). Its README documents a `data` array with each fuel's name, `region1`, `region2`, unit, and `meta.priceDate`; the adapter expands the two regions into separate records. The repository is marked MIT, but separate data-use terms and this deployment's live response were not verified. The app keeps the API provider attribution and does not claim government ownership of the upstream data.

| Method | Path | State |
|---|---|---|
| GET | `/health` | Implemented, process liveness |
| GET | `/ready` | Implemented, Mongo connection readiness |
| GET | `/api/v1/fuels` | Implemented |
| GET | `/api/v1/prices/latest?region=REGION_1` | Implemented |
| GET | `/api/v1/prices/compare-regions` | Implemented |
| GET | `/api/v1/prices/:fuelCode?region=REGION_1` | Implemented |
| GET | `/api/v1/history?fuelCode=RON_95_III&region=REGION_1&period=30d` | Implemented, coverage marked incomplete |
| GET | `/api/v1/analytics/summary` | Basic summary implemented |
| GET | `/api/v1/analytics/compare?region=REGION_1&unit=liter` | Implemented |
| GET | `/api/v1/metadata` | Implemented |
| POST | `/api/v1/internal/sync` | Implemented, `Authorization: Bearer ...` required |
| POST | `/api/v1/internal/history/import` | Returns 501 until a verified history source exists |
| POST | `/api/v1/internal/notifications/retry` | Implemented, protected outbox batch retry |
| POST | `/api/v1/devices/register` | Implemented; returns a one-time installation credential |
| GET/PUT | `/api/v1/devices/:installationId/preferences` | Implemented; requires `X-Installation-Credential` |
| PUT | `/api/v1/devices/:installationId/token` | Implemented; stores a validated FCM token, but delivery is pending |
| DELETE | `/api/v1/devices/:installationId` | Implemented; deactivates an authenticated device |

Firebase Admin delivery and a bounded MongoDB notification outbox are implemented behind optional Firebase configuration. The mobile client does not yet register devices or request notification permission, so end-to-end push is not active in this build. The minimal OpenAPI document is at `/openapi.json` and `/docs`; a full Swagger UI is not installed.
