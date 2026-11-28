# Deployment

## Local backend

1. Install Node.js 22 and Docker Desktop (or use an Atlas development database).
2. Copy `backend/.env.example` to `backend/.env`; set `MONGODB_URI` and a long random `SYNC_SECRET`.
3. Run `cd backend; npm ci; npm run dev`.
4. Check `/health` and `/ready`. `/health` does not prove the database is connected.

For local MongoDB, `docker compose up --build` binds MongoDB only to loopback and stores data in a named volume. Alternatively set a valid Atlas URI in the local environment. Never commit `.env`.

## MongoDB Atlas

Create/use a cluster, make sure it is running, create a database user with least privilege for `viet_fuel`, allow the backend's outbound IP or a deliberately chosen network rule, and set the URI as Render's `MONGODB_URI`. Check `/ready` after deployment. The Atlas account currently available in this workstation exposes a paused free cluster whose hostname differs from the URI supplied in chat; no connection was made. Resume the intended cluster and verify the hostname and credentials in Atlas before deploying.

Credentials pasted into a chat should be considered exposed; rotate the database password and update Render/local secret storage before production use.

## Render

Connect the Git repository and create a Blueprint from `render.yaml`. Add `MONGODB_URI` and `SYNC_SECRET` in Render's secret environment settings. `UPSTREAM_BASE_URL` is configured in the Blueprint. Deploy, then verify `/health` and `/ready`. The free web service may sleep between requests; a cold start delays the first response.

## GitHub Actions sync

Set repository variable `BACKEND_URL` to the Render origin and repository secret `SYNC_SECRET` to the same secret configured on Render. `fuel-price-sync.yml` runs every 15 minutes (UTC) and supports manual dispatch. Schedules may be delayed or disabled for inactive repositories.

## Mobile

The app defaults to the deployed API at `https://viet-fuel-api.onrender.com`.
Override `API_BASE_URL` only when pointing at a local development backend:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Production builds can use the default URL:

```sh
flutter build apk --release
flutter build appbundle --release
```

iOS builds require macOS/Xcode and signing setup. Firebase project credentials and push configuration are not currently wired into the app.
