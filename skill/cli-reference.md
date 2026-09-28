# @proton/cli Reference

Complete command reference for the Proton CLI tool used for XPR Network smart contract development, deployment, and blockchain interaction.

## Installation

```bash
npm i -g @proton/cli
# or
yarn global add @proton/cli
```

**Requires Node.js 16+**

If you get permission errors on Mac/Linux, install Node under your own user instead of `sudo chown`-ing system directories — use [nvm](https://github.com/nvm-sh/nvm), or point npm at a user-owned prefix:
```bash
npm config set prefix ~/.npm-global
export PATH="$HOME/.npm-global/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
npm i -g @proton/cli
```

---

## Network Configuration

```bash
# List available networks
proton chain:list

# Get current network
proton chain:get
# or
proton network

# Switch to mainnet
proton chain:set proton

# Switch to testnet
proton chain:set proton-test

# Get chain info (head block, etc.)
proton chain:info

# Get current RPC endpoint
proton endpoint:get

# Set custom RPC endpoint
proton endpoint:set https://proton.eosusa.io

# Restore default endpoint
proton endpoint:default
```

---

## Key Management

Keep private keys out of code and config files. Anything that reads a key into the process is the leak surface the keychain pattern in `backend-patterns.md` → *Security: Key Isolation* exists to close.

```bash
# Generate new key pair
proton key:generate

# Add existing private key (interactive)
proton key:add

# Add key directly (will prompt for encryption)
# Passing the key as an argument writes it to shell history and exposes it in `ps`
# while the command runs — prefer interactive `proton key:add` wherever there's a TTY.
proton key:add PVT_K1_xxxxx

# Add key without encryption prompt (same argv exposure as above)
# Answering "no" leaves the key plaintext in proton-cli.json until you run `proton key:lock`.
echo "no" | proton key:add PVT_K1_xxxxx

# List all stored keys
proton key:list

# Get private key for a public key
# Prints the raw private key to stdout — never run this in an agent session, CI job,
# or anything else that captures or logs command output.
proton key:get PUB_K1_xxxxx

# Lock keys with password
proton key:lock

# Unlock keys
proton key:unlock [PASSWORD]

# Remove a specific key
proton key:remove PVT_K1_xxxxx

# Reset password and delete ALL keys
proton key:reset
```

### Key Storage Location

- **Keys + config**: one file, `proton-cli.json`, in the OS config directory — macOS `~/Library/Preferences/@proton/cli-nodejs/`, Linux `~/.config/@proton/cli-nodejs/`. Private keys live in its `privateKeys` array and are encrypted in place when the store is locked (`proton key:lock`). There is no `~/.proton-cli` directory.

---

## Account Management

```bash
# Get account info
proton account myaccount

# Get account with token balances
proton account myaccount -t

# Get raw account data (JSON)
proton account myaccount -r

# Create new account (email verification)
proton account:create newaccount

# Create an account paid for by one you control (no email; prints no private key when -k is given)
proton account:create-funded newaccount -c creator -k PUB_K1_xxxxx -o backupowner

# Update account permissions
proton permission myaccount

# Link permission to contract action
proton permission:link myaccount mypermission mycontract

# Unlink permission
proton permission:unlink myaccount mycontract
```

---

## Smart Contract Deployment

### Build Contract

Contract files must be named `*.contract.ts` and compiled with `proton-asc`:

```bash
# Build command (in package.json)
npx proton-asc ./assembly/mycontract.contract.ts

# Output files in assembly/target/:
# - mycontract.contract.wasm
# - mycontract.contract.abi
```

### Deploy Contract

```bash
# Deploy WASM + ABI (looks for *.wasm and *.abi in target dir)
proton contract:set mycontract ./assembly/target

# Deploy only WASM
proton contract:set mycontract ./assembly/target -w

# Deploy only ABI
proton contract:set mycontract ./assembly/target -a

# Get contract ABI
proton contract:abi mycontract

# Clear contract (remove WASM + ABI)
proton contract:clear mycontract

# Clear only ABI
proton contract:clear mycontract -a

# Clear only WASM
proton contract:clear mycontract -w

# Enable inline actions on contract
proton contract:enableinline mycontract
```

> **`contract:set` is interactive and can half-succeed** (`@proton/cli` 0.1.98):
> - It asks `Continue? (y/N)` and has no `--yes` flag. In a script or agent session, pipe the answer in:
>   `echo y | proton contract:set mycontract ./assembly/target`. Without it, nothing is deployed.
> - It can publish the ABI even when the node rejects the WASM, and it still **exits 0**. An account in that
>   state reports every action as `"status": "executed"`, but nothing runs. Check the code hash after every
>   deploy. All zeros means there is no code:
>
>   ```bash
>   curl -s -X POST https://proton.eosusa.io/v1/chain/get_code_hash -d '{"account_name":"mycontract"}'
>   ```

### Deployment Workflow

```bash
# 1. Set network
proton chain:set proton

# 2. Add private key
proton key:add

# 3. Build contract
npm run build

# 4. Check RAM (WASM requires ~100-200KB)
proton account mycontract

# 5. Buy RAM if needed
proton ram:buy mycontract mycontract 200000 -p mycontract@active

# 6. Deploy (answers the Continue? prompt), then confirm code_hash is not all zeros
echo y | proton contract:set mycontract ./assembly/target
curl -s -X POST https://proton.eosusa.io/v1/chain/get_code_hash -d '{"account_name":"mycontract"}'

# 7. Initialize
proton action mycontract init '{"owner":"mycontract"}' mycontract
```

---

## Executing Actions

```bash
# Basic syntax
proton action CONTRACT ACTION 'DATA_JSON' AUTHORIZATION

# Authorization format: account or account@permission (defaults to @active)
```

### Examples

```bash
# Token transfer
proton action eosio.token transfer \
  '{"from":"alice","to":"bob","quantity":"1.0000 XPR","memo":"test"}' \
  alice

# Initialize contract
proton action mycontract init '{"owner":"mycontract"}' mycontract

# Vote for block producers
proton action eosio voteproducer \
  '{"voter":"myaccount","proxy":"","producers":["bp1","bp2","bp3","bp4"]}' \
  myaccount

# Update permissions
proton action eosio updateauth '{
  "account":"mycontract",
  "permission":"active",
  "parent":"owner",
  "auth":{
    "threshold":1,
    "keys":[{"key":"PUB_K1_xxx","weight":1}],
    "accounts":[
      {"permission":{"actor":"mycontract","permission":"eosio.code"},"weight":1}
    ],
    "waits":[]
  }
}' mycontract@owner
```

---

## Querying Tables

```bash
# Basic table query
proton table CONTRACT TABLE [SCOPE]

# Default scope is same as contract
proton table eosio.proton usersinfo
proton table eosio.proton usersinfo eosio.proton  # Explicit scope
```

### Query Options

```bash
# Limit rows
proton table mycontract mytable -c 10

# Lower bound (filter by primary key >=)
proton table mycontract mytable -l 100

# Upper bound (filter by primary key <=)
proton table mycontract mytable -u 200

# Exact match (lower = upper)
proton table mycontract mytable -l mykey -u mykey

# Reverse order
proton table mycontract mytable -r

# Use secondary index
proton table mycontract mytable -i 2

# Show RAM payer
proton table mycontract mytable -p
```

### Common Table Queries

```bash
# User profile from eosio.proton
proton table eosio.proton usersinfo -l alice -u alice

# Token balance
proton table eosio.token accounts alice

# Oracle price (BTC/USD = index 4)
proton table oracles data -l 4 -u 4
```

---

## Transactions

```bash
# Sign a raw transaction with the keychain and broadcast it
# (takes UNSIGNED {"actions":[...]} JSON; signs with the stored key)
proton transaction:push '{"actions":[...]}'

# Get transaction by ID
proton transaction:get TRANSACTION_ID

# Note: bare `proton transaction '<json>'` does not JSON.parse its argument
# and fails on a JSON string — use transaction:push for raw transactions.

# transaction:push needs the {"actions":[...]} wrapper. For a file that holds
# only one action's data, use `proton action` instead:
proton action CONTRACT ACTION "$(cat data.json)" AUTHORIZATION

# Push to specific endpoint
proton transaction:push TX_JSON -u https://proton.eosusa.io
```

### Scripting the CLI for bulk or high-value jobs

Checked against `@proton/cli` 0.1.98 and 0.1.99 source, and used for a 3,333-asset AtomicAssets mint on testnet
and mainnet (September 2026):

- **Errors still exit 0.** `transaction:push`, `action` and `contract:set` catch the error, print it (in red,
  with a hint) and return normally. A script must parse stdout. Success prints a JSON result with a 64-hex
  `"transaction_id"`. No `transaction_id` means the command failed or its outcome is unknown.
- **Transactions expire after 3,000 s (50 min).** The CLI signs with `expireSeconds: 3000` and TAPOS from the
  last irreversible block. A transaction whose outcome you don't know can still land for up to 50 minutes.
- **Header fields you supply win.** `@proton/js` builds the header as `{ ...generatedHeader, ...yourJson }`, so
  `expiration`, `ref_block_num` and `ref_block_prefix` in the JSON you pass to `transaction:push` replace the
  CLI's. Set your own short expiration (for example head block time + 10 min) and record it *before* you
  push. You then know exactly when an unanswered push can no longer land.
- **The error text tells you whether anything was broadcast.** The CLI calls `get_info`, `get_block` /
  `get_block_info`, `get_abi` / `get_raw_abi` and `get_required_keys` before it signs and sends. An error
  that names one of those read calls (and not `push_transaction` / `send_transaction`) means nothing was
  sent, so it is safe to retry at once, on another endpoint. A node rejection (`assertion failure`,
  `transaction net usage is too high`, `tx_cpu_usage_exceeded`, `billed CPU time`, `ram_usage_exceeded`,
  `missing authority`) means the node ran it and refused it. It was not accepted, so it can't land later. Fix
  the cause and retry. **Anything else is ambiguous**: a timeout, a dropped connection, or output with no
  `transaction_id` and no recognizable error.
- **Never resend an ambiguous push blindly.** Read the state the transaction was supposed to change. If it
  changed, the push landed. If it didn't, wait until an endpoint's `last_irreversible_block_time` is past the
  transaction's expiration, read the state again **from that same endpoint**, and only then resend. With the
  CLI's default header that is a ~52-minute pause; with your own 10-minute expiration it is ~13 minutes.
- **The selected network is global.** `proton chain:set` writes the CLI's shared config, so another shell or
  agent session can switch it under your script. Run `proton chain:get` (or compare `get_info.chain_id` from
  the endpoint you pass with `-u`) immediately before every signing step, and stop on a mismatch.

A resend-safe loop for a job whose state you can read, for example AtomicAssets `issued_supply` for a
template (see `nfts-atomicassets.md` → *Bulk minting safely*):

```text
for each batch, in order:
  read the state; if this batch is already reflected, skip it
  if an earlier attempt for this batch is unresolved: resend only after an endpoint's LIB time > its expiration
  build the tx with your own expiration + TAPOS; append {batch, expiration} to a journal and fsync
  proton transaction:push '<tx json>' -u <endpoint>   # parse stdout, ignore the exit code
  poll the state for ~30 s:
    moved as expected               -> journal "done"
    unchanged + pre-broadcast error -> journal "not sent", retry on the next endpoint
    unchanged + node rejection      -> journal "rejected", stop and fix the cause
    anything else                   -> journal "ambiguous", stop (the next run waits out the expiry)
```

---

## Code Generation (Boilerplate)

```bash
# Create new project with contract, frontend, tests
proton boilerplate myproject

# Generate new contract
proton generate:contract mycontract

# Add action to contract
proton generate:action

# Add table to contract
proton generate:table mytable

# Add singleton table
proton generate:table myconfig -s

# Add inline action class
proton generate:inlineaction myaction
```

---

## Resource Management

```bash
# Get RAM price
proton ram

# Buy RAM (bytes)
proton ram:buy BUYER RECEIVER BYTES -p BUYER@active

# Example: Buy 150KB for contract
proton ram:buy mycontract mycontract 150000 -p mycontract@active

# Buy a CPU/NET plan from the `resources` contract: deposit first, then buyplan
# (the deposit is credited to the sender; plan_index 0 = Basic, 100 XPR, 744 h)
proton action eosio.token transfer '{"from":"myaccount","to":"resources","quantity":"100.0000 XPR","memo":""}' myaccount
proton action resources buyplan '{"account":"myaccount","plan_index":0,"plan_quantity":1}' myaccount
proton account myaccount   # NET/CPU limits should now be far above the free allowance

# List faucets
proton faucet

# Claim from faucet (testnet: 1,000 test XPR per account per 24 h)
proton faucet:claim XPR myaccount
```

---

## Multisig Operations

```bash
# Create multisig proposal
proton msig:propose myproposal '[{"account":"eosio.token","name":"transfer",...}]' proposer

# Approve proposal
proton msig:approve proposer myproposal approver

# Execute approved proposal
proton msig:exec proposer myproposal executor

# Cancel proposal
proton msig:cancel myproposal proposer
```

---

## Utility Commands

```bash
# Encode account name to u64
proton encode:name myaccount

# Encode token symbol
proton encode:symbol XPR 4

# Open account in Proton Scan
proton scan myaccount

# Create session from Proton Sign Request URI
proton psr "proton://..."

# Get CLI version
proton version

# Get help for any command
proton --help
proton [COMMAND] --help
```

---

## Common Issues & Solutions

### "Key not found" Error

```bash
proton key:list  # Check if key is stored
proton key:add   # Add the key
```

### "Authorization error"

- Check account has correct permissions
- Verify key matches account's active key
- Try explicit permission: `account@active`

### "Transaction failed"

- Check account has enough RAM: `proton account myaccount`
- Check account has enough CPU/NET
- Verify action parameters match ABI

### WebAuthn Keys (PUB_WA_) Cannot Be Used

If an account's active key is WebAuthn (starts with `PUB_WA_`), you cannot sign from CLI. Update permission to use K1 key:

```bash
proton action eosio updateauth '{
  "account":"ACCOUNT",
  "permission":"active",
  "parent":"owner",
  "auth":{
    "threshold":1,
    "keys":[{"key":"PUB_K1_xxx","weight":1}],
    "accounts":[{"permission":{"actor":"ACCOUNT","permission":"eosio.code"},"weight":1}],
    "waits":[]
  }
}' ACCOUNT@owner
```

### RAM Requirements

WASM files require significant RAM. Check before deploying:

```bash
proton account mycontract  # Check available RAM
proton ram                 # Check RAM price
proton ram:buy mycontract mycontract 150000 -p mycontract@active
```

### Misleading Error Messages

Some commands show errors but still succeed. Always check the transaction link in output:
- `"Error: Inline actions already enabled"` may appear on successful deploy

In scripts, **don't grep the output for `error`**. Successful transactions include `"error_code": null`. Look
for `"status": "executed"` to confirm success, and for `assertion failure` to catch a contract rejection. Don't
rely on the exit code: the CLI prints RPC and contract errors and still exits 0, and `contract:set` can exit 0
after a failed WASM deploy (see *Deploy Contract* and *Scripting the CLI for bulk or high-value jobs*).

Even `"status": "executed"` with a `transaction_id` only means the endpoint you pushed to ran the
transaction. It can still fail to land. See `troubleshooting.md` → *A push returned a transaction_id, but
nothing changed on chain*.

### ram:buy Syntax

Authorization uses `-p` flag, not positional:

```bash
# Correct
proton ram:buy BUYER RECEIVER BYTES -p BUYER@active

# Incorrect (will fail)
proton ram:buy BUYER RECEIVER BYTES BUYER
```

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Set mainnet | `proton chain:set proton` |
| Set testnet | `proton chain:set proton-test` |
| Add key | `proton key:add` |
| Account info | `proton account NAME -t` |
| Deploy contract | `echo y \| proton contract:set ACCOUNT ./assembly/target` |
| Execute action | `proton action CONTRACT ACTION 'JSON' AUTH` |
| Query table | `proton table CONTRACT TABLE` |
| Buy RAM | `proton ram:buy PAYER RECV BYTES -p PAYER@active` |
| Enable inline | `proton contract:enableinline CONTRACT` |


---

## The CLI resolves a contract's ABI BEFORE executing the transaction

`proton transaction:push` serializes every action against the ABI currently on chain. So a single transaction
cannot both deploy a contract and call one of its new actions:

```
Unknown action clearall in contract mycontract
```

Split it: `setcode` + `setabi` in one transaction, the new action in the next. The same applies to `setconfig`
style bootstrapping — the contract must already be live before its own actions can be serialized, which is also
why a multisig proposal to call a not-yet-deployed action cannot even be created.
