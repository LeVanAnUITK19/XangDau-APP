# Database design

Database name: `viet_fuel`.

| Collection | Purpose | Indexes |
|---|---|---|
| `fuels` | Stable fuel codes, names, categories and units | Unique `code` |
| `price_records` | One observed price per source, fuel, region and effective period | Unique `recordKey`; compound fuel/region/source/effective time and date |
| `latest_prices` | Current effective prices by source, fuel and region | Unique fuel/region/source |
| `sync_state` | Latest successful sync and an expiring synchronization lock | Unique `key` |

All values and timestamps are validated by Mongoose. The sync process stores an observed timestamp separately from the upstream effective date/time. It must never assign a fabricated effective time. Notification/device collections are deferred until the delivery lifecycle is implemented.
