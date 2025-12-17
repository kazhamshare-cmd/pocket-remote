# RemoteTouch Android Signing Key Information

## Keystore Details

- **Keystore File:** `remotetouch-release.keystore`
- **Keystore Location:** `/Users/ikushimakazuyuki/pocket-remote/mobile/android/remotetouch-release.keystore`
- **Key Alias:** `remotetouch`
- **Store Password:** `remotetouch2024`
- **Key Password:** `remotetouch2024`
- **Validity:** 10,000 days (approximately 27 years)
- **Key Algorithm:** RSA 2048-bit
- **Signature Algorithm:** SHA256withRSA

## Certificate Details

- **CN (Common Name):** RemoteTouch
- **OU (Organizational Unit):** Development
- **O (Organization):** B19
- **L (Locality):** Tokyo
- **ST (State):** Tokyo
- **C (Country):** JP

## key.properties Content

```
storePassword=remotetouch2024
keyPassword=remotetouch2024
keyAlias=remotetouch
storeFile=remotetouch-release.keystore
```

## Important Notes

1. **DO NOT** commit the keystore file or key.properties to public repositories
2. Keep this information secure - losing the keystore means you cannot update the app on Google Play
3. The keystore file should be backed up in a secure location
4. Created: 2024-12-17
