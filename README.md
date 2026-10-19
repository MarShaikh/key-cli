# key

Stores API keys in the macOS login keychain. Reading, replacing or deleting one requires Touch ID, or the login password when Touch ID is unavailable.

```sh
key set OPENAI_API_KEY        # prompts without echo; or: pbpaste | key set OPENAI_API_KEY
getkey OPENAI_API_KEY         # Touch ID, then prints the key (same as: key get)
key ls                        # names only, no auth
key rm OPENAI_API_KEY
key adopt anthropic           # move a key stored by the old zsh function
```

Install: `make install` (into `~/.local/bin`, plus a `getkey` symlink).

## Why another tool can't bypass it

The keychain item is created by this binary, so its ACL trusts only this binary. Any other process gets the keychain-password dialog, including `security find-generic-password -w`. The Touch ID check lives inside the binary, and the ACL is pinned to its code hash, so a patched copy is a different binary and also gets the dialog.

Keys stored by the old zsh function trust `/usr/bin/security`, so anyone can read them without a prompt. `key adopt` re-creates them under this binary.

## Caveats

- **After a rebuild**, the code hash changes. The first `get` of each key then shows a "key wants to use…" dialog. Enter the login password and choose Always Allow.
- **The protection only holds while your login password is secret.** Someone who knows it can approve the keychain dialog.
- **Each `getkey` asks for Touch ID**, so a script that reads five keys prompts five times.
