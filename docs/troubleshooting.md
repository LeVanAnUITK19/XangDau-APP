# Troubleshooting

- **`/ready` returns 503:** confirm `MONGODB_URI`, Atlas cluster state, user password escaping, database role and network access.
- **Sync reports an unsupported payload:** compare the hosted response to VietFuelAPI's documented `data` rows (`name`, `region1`, `region2`, `unit`) and `meta.priceDate`; update `normalizePayload` using a sanitized fixture. The importer intentionally refuses unrecognized shapes.
- **No prices show:** empty data is expected before a verified successful sync; the app does not seed production mock prices.
- **Android emulator cannot reach local API:** use `http://10.0.2.2:3000`; a physical device needs a reachable development host address.
- **Render first request is slow:** free web services can cold-start. The app has request timeouts and locally cached responses when available.
- **Flutter tools stall:** check Flutter SDK cache initialization and run `flutter doctor -v` from a terminal with access to the installed SDK.
- **Notifications do not arrive:** push registration/FCM delivery is not implemented yet; enabling the local setting is not a device subscription.
