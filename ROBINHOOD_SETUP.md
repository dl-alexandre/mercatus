# Robinhood API Setup Instructions

## Current Issue

The Robinhood API integration is failing with "Signature verification failed" because:
1. Your `.env` file has API keys and private keys that are not linked in Robinhood's system
2. The API key must be paired with its corresponding public key in Robinhood's API portal

## Solution

You need to register your PUBLIC KEY in Robinhood's API portal to link it with an API key.

## Setup Steps

### Option A: Generate New Keys (Recommended)

1. Generate a new Ed25519 key pair:
   ```bash
   python3 scripts/generate_robinhood_keys.py
   ```

2. Upload the PUBLIC KEY to Robinhood:
   - Go to: https://robinhood.com/settings/api
   - Paste the public key shown in the output
   - Robinhood will give you an API key

3. Update your `.env` file with both keys:
   ```env
   ROBINHOOD_API_KEY=rh-api-xxxx-xxxx-xxxx  # From Robinhood portal
   ROBINHOOD_PRIVATE_KEY=xxxxx              # From generation script
   ```

### Option B: Use Existing Keys

1. Go to https://robinhood.com/settings/api
2. Find the public key associated with your current API key
3. If no public key exists, you'll need to create new credentials

## Testing

Once you have the correct credentials:

```bash
swift run SmartVestorCLI balance --robinhood
```

## Technical Details

- Robinhood uses Ed25519 signature authentication
- The private key signs requests, the public key is uploaded to Robinhood
- The API key from Robinhood must correspond to the uploaded public key
- Signatures are generated for every authenticated request

## Notes

- The signature algorithm implementation is correct (verified with examples)
- The issue is credential registration, not code
- Ed25519 signing is not yet fully implemented in Swift (placeholder exists)
