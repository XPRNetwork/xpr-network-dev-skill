# WebAuth and Identity on XPR Network

This guide covers WebAuth wallet integration, user profiles, and KYC/identity verification.

## WebAuth Overview

WebAuth is XPR Network's native wallet supporting:
- **WebAuthn authentication** - Face ID, fingerprint, security keys
- **Account abstraction** - Human-readable accounts
- **No seed phrases** - Hardware-backed keys
- **Cross-device** - Mobile app and web wallet

### Wallet Options

| Wallet | Type | Use Case |
|--------|------|----------|
| WebAuth Mobile | iOS/Android app | Primary consumer wallet |
| webauth.com | Web wallet | Browser-based, no install |
| Anchor | Desktop app | Power users, developers |

---

## User Profiles

User profiles are stored in the `eosio.proton` contract.

### Profile Table Structure

```typescript
interface UserInfo {
  acc: string;           // Account name
  name: string;          // Display name
  avatar: string;        // Avatar URL or base64
  verified: boolean;     // Opt-in display checkmark set by a verifier account — NOT a KYC summary (fully KYC'd accounts routinely have verified=false)
  date: number;          // Registration date
  verifiedon: number;    // Verification timestamp
  verifier: string;      // Account that verified
  raccs: string[];       // Recovery accounts
  aacts: { field_0: string; field_1: string }[];  // ABI: tuple_name_name[]
  ac: { field_0: string; field_1: string }[];     // ABI: tuple_name_string[]
  kyc: KYCProvider[];    // KYC verifications
}

interface KYCProvider {
  kyc_provider: string;  // Provider account
  kyc_level: string;     // Comma-separated CLAIM list, e.g. "metal.kyc:address,metal.kyc:selfie,..." — NOT a numeric level; parseInt() returns NaN
  kyc_date: number;      // Verification date
}
```

### Query User Profile

```typescript
async function getUserProfile(account: string) {
  const { rows } = await rpc.get_table_rows({
    code: 'eosio.proton',
    scope: 'eosio.proton',
    table: 'usersinfo',
    lower_bound: account,
    upper_bound: account,
    limit: 1
  });

  return rows[0] ?? null;
}

// Example response
{
  "acc": "alice",
  "name": "Alice",
  "avatar": "https://gateway.pinata.cloud/ipfs/Qm...",
  "verified": false,
  "date": 1704567890,
  "verifiedon": 0,
  "verifier": "",
  "raccs": [],
  "aacts": [],
  "ac": [],
  "kyc": [
    {
      "kyc_provider": "metal.kyc",
      "kyc_level": "metal.kyc:address,metal.kyc:birthdate,metal.kyc:selfie,metal.kyc:frontofid,metal.kyc:backofid,metal.kyc:firstname,metal.kyc:lastname",
      "kyc_date": 1705123456
    }
  ]
}
```

This is the real shape on mainnet (read from `eosio.proton::usersinfo`, 2026-09): `kyc_level` is a **comma-separated list of claims** issued by the provider, and `verified` is independent of KYC — accounts with a full 7-claim KYC record commonly have `verified: false`.


### Check KYC Status

```typescript
async function isKYCVerified(account: string): Promise<boolean> {
  const profile = await getUserProfile(account);

  if (!profile) return false;

  // Check for any KYC entry
  return profile.kyc && profile.kyc.length > 0;
}

/** All KYC claims across providers, e.g. ["metal.kyc:address", "metal.kyc:selfie", ...] */
async function getKYCClaims(account: string): Promise<string[]> {
  const profile = await getUserProfile(account);
  if (!profile?.kyc?.length) return [];
  return profile.kyc.flatMap(k =>
    k.kyc_level.split(',').map(c => c.trim()).filter(Boolean)
  );
}

/** Check for a specific claim, e.g. hasKYCClaim(acct, 'metal.kyc:selfie') */
async function hasKYCClaim(account: string, claim: string): Promise<boolean> {
  return (await getKYCClaims(account)).includes(claim);
}

/**
 * DERIVED tier — there is no numeric level on chain. This is one reasonable
 * mapping from claim count; define your own thresholds for your risk model.
 */
async function getKYCTier(account: string): Promise<0 | 1 | 2> {
  const claims = await getKYCClaims(account);
  const hasId = claims.some(c => /frontofid|backofid/.test(c));
  if (claims.length === 0) return 0;          // no KYC
  if (hasId && claims.length >= 5) return 2;  // full identity KYC
  return 1;                                   // partial claims
}
```

### KYC Claims

`kyc_level` is a claim list, not a level. Claims observed on mainnet from the `metal.kyc` provider:

| Claim | Meaning |
|-------|---------|
| `metal.kyc:firstname`, `metal.kyc:lastname` | Legal name verified |
| `metal.kyc:birthdate` | Date of birth verified |
| `metal.kyc:address` | Residential address verified |
| `metal.kyc:frontofid`, `metal.kyc:backofid` | Government ID document captured |
| `metal.kyc:selfie` | Liveness / selfie match |
| `metal.kyc:nationalidnumber` | National ID number verified (present in 2026 issuances, sometimes instead of `backofid`) |
| `trulioo:address`, `trulioo:birthdate`, `trulioo:firstname`, `trulioo:lastname` | Legacy 2021–2023 records (still issued under `kyc_provider: metal.kyc`); no ID-document claims |

A current full KYC record carries 7–8 `metal.kyc:*` claims and claim order varies; the same provider has issued different claim sets over time. Always split on `,` and match by string rather than assuming a fixed set.

> **Don't `parseInt(kyc_level)`.** It returns `NaN` for every real account, so `Math.max(...)` is `NaN` and any `>= n` check is `false` — a gate written that way silently fails closed (or open, depending on how you branch). Earlier versions of this doc had exactly that bug.

---

## Update User Profile

The `eosio.proton` contract uses two separate actions for updating profile fields:
- `setusername` to update the display name
- `setuserava` to update the avatar

Both can be submitted in a single transaction:

```typescript
async function updateProfile(
  session: any,
  name: string,
  avatar: string
) {
  return session.transact({
    actions: [
      {
        account: 'eosio.proton',
        name: 'setusername',
        authorization: [session.auth],
        data: {
          acc: session.auth.actor,
          name: name
        }
      },
      {
        account: 'eosio.proton',
        name: 'setuserava',
        authorization: [session.auth],
        data: {
          acc: session.auth.actor,
          ava: avatar
        }
      }
    ]
  }, { broadcast: true });
}
```

---

## Display User Info

### Avatar Component

Local initials fallback — no third-party CDN, no per-render request leaking account names to an external service. Account name hashes to a deterministic hue so each user gets a consistent color.

```tsx
interface AvatarProps {
  account: string;
  avatar?: string;
  size?: number;
}

// Cheap, deterministic string → hue.
function hueFromAccount(account: string): number {
  let hash = 0;
  for (let i = 0; i < account.length; i++) {
    hash = (hash << 5) - hash + account.charCodeAt(i);
    hash |= 0; // force int32
  }
  return Math.abs(hash) % 360;
}

export function Avatar({ account, avatar, size = 40 }: AvatarProps) {
  const [error, setError] = useState(false);
  const showImage = avatar && !error;

  if (showImage) {
    return (
      <img
        src={avatar}
        alt={account}
        width={size}
        height={size}
        style={{ borderRadius: '50%', objectFit: 'cover' }}
        onError={() => setError(true)}
      />
    );
  }

  // Initials fallback — first character of the account, in a deterministic-color circle.
  const hue = hueFromAccount(account);
  return (
    <div
      role="img"
      aria-label={account}
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        background: `hsl(${hue}, 60%, 50%)`,
        color: 'white',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: size * 0.45,
        fontWeight: 600,
        textTransform: 'uppercase',
        userSelect: 'none',
      }}
    >
      {account.charAt(0)}
    </div>
  );
}
```

### User Card Component

```tsx
interface UserCardProps {
  account: string;
}

export function UserCard({ account }: UserCardProps) {
  const [profile, setProfile] = useState<UserInfo | null>(null);

  useEffect(() => {
    async function load() {
      const p = await getUserProfile(account);
      setProfile(p);
    }
    load();
  }, [account]);

  const isKYC = profile?.kyc?.length > 0;

  return (
    <div className="user-card">
      <Avatar account={account} avatar={profile?.avatar} size={60} />
      <div>
        <h3>{profile?.name || account}</h3>
        <span className="account">@{account}</span>
        {/* `verified` is an opt-in display flag, independent of KYC — most KYC'd accounts have it false */}
        {profile?.verified && <span className="checkmark">✓ Verified</span>}
        {isKYC && <span className="kyc-badge">KYC</span>}
      </div>
    </div>
  );
}
```

---

## WebAuth SDK Integration

### Login Flow

```typescript
import ProtonWebSDK from '@proton/web-sdk';

async function login() {
  const { link, session } = await ProtonWebSDK({
    linkOptions: {
      chainId: '384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0',
      endpoints: ['https://proton.eosusa.io'],
      restoreSession: false
    },
    transportOptions: {
      requestAccount: 'myapp'
    },
    selectorOptions: {
      appName: 'My App',
      appLogo: 'https://myapp.com/logo.png',
      enabledWalletTypes: ['proton', 'webauth', 'anchor']
    }
  });

  // Get user profile after login
  const profile = await getUserProfile(session.auth.actor);

  return {
    session,
    profile,
    isKYC: profile?.kyc?.length > 0
  };
}
```

### Require KYC for Actions

```typescript
async function requireKYC(session: any) {
  const profile = await getUserProfile(session.auth.actor);

  if (!profile?.kyc?.length) {
    throw new Error('KYC verification required. Please verify your identity in WebAuth.');
  }

  return true;
}

// Usage
async function performKYCAction(session: any, data: any) {
  await requireKYC(session);

  // Proceed with action
  return session.transact({
    actions: [/* ... */]
  });
}
```

### Deep Link to WebAuth

```typescript
// Redirect to WebAuth for KYC
function redirectToKYC() {
  window.location.href = 'https://webauth.com/verify';
}

// Open specific account in WebAuth
function openInWebAuth(account: string) {
  window.location.href = `https://webauth.com/wallet/${account}`;
}
```

---

## Verification in Contracts

### Check KYC On-Chain

```typescript
import { Name, Table, TableStore, check, requireAuth } from 'proton-tsc';

// Define the usersinfo table structure
@table("usersinfo", noabigen)
class UserInfo extends Table {
  constructor(
    public acc: Name = new Name(),
    public name: string = "",
    public avatar: string = "",
    public verified: boolean = false
    // kyc array handling requires custom deserialization
  ) { super(); }

  @primary
  get primary(): u64 { return this.acc.N; }
}

@action("kycaction")
kycRequiredAction(user: Name): void {
  requireAuth(user);

  // Query eosio.proton usersinfo
  const usersTable = new TableStore<UserInfo>(
    Name.fromString("eosio.proton"),
    Name.fromString("eosio.proton").N
  );

  const userInfo = usersTable.get(user.N);
  check(userInfo != null, "User not found");
  check(userInfo.verified, "User must be verified");

  // Proceed with action...
}
```

---

## Privacy Considerations

### Minimal Data Collection

```typescript
// Only request what you need
const profile = await getUserProfile(account);

// Don't store KYC details
const publicProfile = {
  account: profile.acc,
  displayName: profile.name,
  avatar: profile.avatar,
  verified: profile.verified
};
```

### User Consent

```tsx
function VerificationRequest() {
  return (
    <div>
      <p>This action requires identity verification.</p>
      <p>We will check your verification status with WebAuth.</p>
      <p>We do not store your personal information.</p>
      <button onClick={checkKYC}>Continue</button>
    </div>
  );
}
```

---

## Quick Reference

### Query User Info

```bash
# Get user profile
proton table eosio.proton usersinfo -l ACCOUNT -u ACCOUNT
```

### Profile Fields

| Field | Description |
|-------|-------------|
| `acc` | Account name |
| `name` | Display name |
| `avatar` | Avatar URL/base64 |
| `verified` | Opt-in display checkmark (set by a verifier) — independent of KYC |
| `kyc` | Array of `{kyc_provider, kyc_level (claim list), kyc_date}` |

### KYC Check Pattern

```typescript
const profile = await getUserProfile(account);
const isKYC = profile?.kyc?.length > 0;
const claims = profile?.kyc?.flatMap(k => k.kyc_level.split(',')) ?? [];
const hasIdDoc = claims.some(c => /frontofid|backofid/.test(c));
// NOT parseInt(kyc_level) — it's a claim list, parseInt gives NaN
```
