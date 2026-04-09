# 02 — Authentication

---

## Overview

Two separate auth mechanisms for two different clients. Each is purpose-built for its use case.

| Client | Auth method | Token lifetime | Storage |
|--------|-------------|----------------|---------|
| Flutter app | JWT (access + refresh) | Access: 15min, Refresh: 30 days | App secure storage (flutter_secure_storage) |
| ESP32 device | Device token (opaque, long-lived) | Until revoked | NVS flash on ESP32 |

---

## Flutter app authentication (JWT)

### Flow

```
1. User opens app -> registration or login screen
2. POST /auth/register  -- creates account, returns JWT pair
   POST /auth/login     -- validates credentials, returns JWT pair
3. App stores tokens in secure storage
4. All REST requests include: Authorization: Bearer <access_token>
5. When access token expires -> POST /auth/refresh with refresh token
6. If refresh token expired -> redirect to login
```

### JWT payload

```json
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "iat": 1714000000,
  "exp": 1714000900
}
```

### Security considerations

- Passwords hashed with bcrypt (cost factor 12)
- Access tokens are short-lived (15 min) to limit exposure
- Refresh tokens are stored server-side (database) and can be revoked
- All REST endpoints (except `/auth/*`) require valid JWT

---

## ESP32 device authentication (device token)

### Flow

```
1. User provisions device via Flutter app (BLE)
2. App calls POST /devices on backend -> receives opaque device token
3. App writes device token to ESP32 over BLE (Device auth service, 0xFFE1)
4. ESP32 stores token in NVS flash (persists across reboots)
5. Every WebSocket connection includes: Authorization: DeviceToken <token>
6. Backend validates token on connection -> maps to device_id and user_id
7. Invalid/revoked token -> WebSocket connection rejected (401)
```

### Token properties

- Opaque string (UUID v4 or crypto-random hex)
- One token per device -- no sharing
- Linked to a user account via the `devices` table
- Revocable from the Flutter app (`DELETE /devices/:id`)
- Revoking a token immediately closes the active WebSocket connection

### Token revocation

When a user deletes a device or revokes its token:

1. Backend marks token as revoked in the database
2. Backend closes any active WebSocket connection for that device
3. ESP32 receives disconnection -> shows offline face
4. Device must be re-provisioned via BLE to get a new token

---

## Auth endpoints

| Method | Endpoint | Auth required | Description |
|--------|----------|---------------|-------------|
| POST | /auth/register | No | Create user account |
| POST | /auth/login | No | Login, receive JWT pair |
| POST | /auth/refresh | Refresh token | Refresh access token |

---

## Related docs

- [06-backend-api.md](06-backend-api.md) — Full API specification
- [08-ble-provisioning.md](08-ble-provisioning.md) — How device tokens are delivered to ESP32
