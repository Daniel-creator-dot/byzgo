# Google Play — Data safety (copy into Play Console)

Use when completing **App content → Data safety** for BytzGo (`com.example.bytzgo`).

## Does your app collect or share user data?

**Yes**

## Data types collected

| Type | Collected | Shared | Purpose | Required? |
|------|-----------|--------|---------|-------------|
| Name | Yes | No | Account | Yes |
| Email | Yes | No | Account, support | Yes |
| Phone number | Yes | No | Account, delivery contact | Yes |
| User IDs | Yes | No | Account | Yes |
| Precise location | Yes | No* | Delivery, rider tracking | Yes for core features |
| Photos | Yes | No | Vendor menu, rider KYC | Optional (vendor/rider) |
| App interactions | Yes | No | Orders, chat | Yes |
| Device or other IDs | Yes | No | Push notifications (FCM) | Optional |

\* Trip data is shown to the matched customer/rider/vendor for fulfilment only — not sold to third parties.

## Security practices

- Data encrypted in transit (HTTPS)
- Users can request account deletion (in-app Profile → Delete account, or https://www.bytzgo.net/account-deletion)

## Privacy policy URL

```
https://www.bytzgo.net/privacy
```

## Account deletion URL

```
https://www.bytzgo.net/account-deletion
```

## Permissions declarations (App content)

| Permission | Reason |
|------------|--------|
| Location | Pickup/drop-off and live trip tracking |
| Notifications | Order and ride alerts |
| Photos / media | Vendor product images; rider ID uploads |
| Full-screen intent | Incoming delivery job alert when phone is locked |

## Target audience

Not designed for children under 13.
