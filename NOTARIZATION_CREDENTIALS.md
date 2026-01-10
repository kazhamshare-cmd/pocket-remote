# macOS Notarization Credentials

## Apple Developer Account
- **Apple ID**: kazham.share@gmail.com
- **Team ID**: G93R2Z67RU
- **Team Name**: BEAK, K.K.

## App-specific Password
- **Password**: pcfl-elbp-comv-ccdo
- Generated from: https://appleid.apple.com

## Code Signing Identity
- **Certificate**: Developer ID Application: BEAK, K.K. (G93R2Z67RU)

## Keychain Profile
- **Profile Name**: notarytool-password

## Usage

### Store credentials (already done)
```bash
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "kazham.share@gmail.com" \
  --team-id "G93R2Z67RU" \
  --password "pcfl-elbp-comv-ccdo"
```

### Submit for notarization
```bash
xcrun notarytool submit <FILE>.dmg --keychain-profile "notarytool-password" --wait
```

### Staple the notarization ticket
```bash
xcrun stapler staple <FILE>.dmg
```

### Verify notarization
```bash
spctl -a -t open --context context:primary-signature -v <FILE>.dmg
```
