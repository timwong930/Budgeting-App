from pathlib import Path

path = Path("Budgeting App/PlaidSyncEngine.swift")
text = path.read_text()

old = '''        let groupedPlaidHoldings = Dictionary(grouping: displayableHoldings) { holding in
            let securityIdentity = holding.securityId ?? normalizedTicker(holding.ticker) ?? holding.name
            return "\\(holding.accountId)|\\(securityIdentity)"
        }
'''
new = '''        let groupedPlaidHoldings = Dictionary(grouping: displayableHoldings) { holding in
            let normalizedSecurityId = holding.securityId.trimmingCharacters(in: .whitespacesAndNewlines)
            let securityIdentity = normalizedSecurityId.isEmpty
                ? (normalizedTicker(holding.ticker) ?? holding.name)
                : normalizedSecurityId
            return "\\(holding.accountId)|\\(securityIdentity)"
        }
'''
if text.count(old) != 1:
    raise RuntimeError(f"security identity marker expected once, found {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                if let securityId = first.securityId,
                   holding.plaidMetadata?.securityId == securityId,
                   holding.plaidMetadata?.accountId == first.accountId {
                    return true
                }
'''
new = '''                let securityId = first.securityId
                if holding.plaidMetadata?.securityId == securityId,
                   holding.plaidMetadata?.accountId == first.accountId {
                    return true
                }
'''
if text.count(old) != 1:
    raise RuntimeError(f"security match marker expected once, found {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
