from pathlib import Path

path = Path("supabase/functions/plaid/index.ts")
text = path.read_text()

old_check = '      if (row.event_type === "cursor-replay-complete") return false;'
new_check = '      if (row.event_type === "ledger-replay-v2-complete") return false;'
if text.count(old_check) != 1:
    raise SystemExit(f"Expected one replay-complete guard, found {text.count(old_check)}")
text = text.replace(old_check, new_check)

old_marker = '          "cursor-replay-complete",\n          "Replayed transaction history after a previously discarded Plaid sync"'
new_marker = '          "ledger-replay-v2-complete",\n          "Replayed transaction history after the account-ledger transfer visibility fix"'
if text.count(old_marker) != 1:
    raise SystemExit(f"Expected one replay log marker, found {text.count(old_marker)}")
text = text.replace(old_marker, new_marker)

path.write_text(text)
