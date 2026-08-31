from pathlib import Path

path = Path("Budgeting App/PlaidAPIClient.swift")
text = path.read_text()
old = "kSecAttrAccessible as String: kSecAccessibleAfterFirstUnlockThisDeviceOnly"
new = "kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
if text.count(old) != 1:
    raise RuntimeError(f"expected one typo, found {text.count(old)}")
path.write_text(text.replace(old, new, 1))
