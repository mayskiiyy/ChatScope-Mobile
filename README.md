# ChatScope Mobile

ChatScope Mobile is a lightweight chat history and filtering script for SA-MP mobile clients that support MoonLoader-compatible Lua scripts, such as MonetLoader-based setups.

It keeps a larger searchable chat history, lets you hide unwanted messages, and organizes messages into custom folders using simple wildcard patterns.

## Features

- Searchable chat history with up to 2,000 stored messages per session
- Three independent filter modes
- Custom folders for VIP chat, advertisements, reports, or any other message category
- `*` wildcard support for dynamic values such as player names, IDs, or amounts
- One-tap message copying from the history window
- Persistent configuration stored in `config/chatscope_mobile.cfg`
- Automatic migration from the old `config/simple_cf.cfg` file

## Commands

| Command | Description |
| --- | --- |
| `/ch` | Opens or closes the chat history window |
| `/cf` | Opens or closes the filter and folder settings |

## Filter modes

### Global

Hides matching messages both from the in-game chat and from ChatScope history.

### Visual only

Hides matching messages from the in-game chat but keeps them in ChatScope history.

### History only

Keeps matching messages in the in-game chat but excludes them from ChatScope history.

## Pattern syntax

Patterns match the entire message. Use `*` to replace any dynamic part.

Examples:

```text
Player * transferred $* to you.
*VIP*
[Advertisement] *
```

All other characters are treated literally, so punctuation such as `.`, `+`, `?`, `[` and `]` does not need manual escaping.

## Folders

Folders show only messages matching one of their patterns. Separate multiple patterns with a semicolon:

```text
*VIP*; *PREMIUM*; [Family] *
```

The semicolon format allows individual patterns to contain spaces. Existing folders created with the original space-separated format remain supported for backward compatibility.

## Installation

1. Make sure your mobile SA-MP client has a MoonLoader-compatible Lua environment and the required libraries:
   - `mimgui`
   - `encoding`
   - `lib.samp.events`
2. Copy `chatscope_mobile.lua` into your script loader directory.
3. For common MonetLoader installations, this directory is usually located under:

```text
Android/media/<your-game-package>/monetloader
```

4. Start the game and use `/ch` or `/cf`.

The exact installation path may differ depending on the client and Android version.

## Configuration

ChatScope creates this file automatically:

```text
config/chatscope_mobile.cfg
```

The configuration is saved whenever a filter or folder is added or removed. If an older `simple_cf.cfg` configuration exists, ChatScope imports it on the first launch.

## Performance

The default history limit is 2,000 messages. On low-end devices, reduce `MAX_HISTORY_LINES` near the top of `chatscope_mobile.lua`.

## Compatibility notes

ChatScope Mobile is designed around MoonLoader-compatible APIs and SA-MP event hooks. Compatibility can vary between mobile clients and loader builds. If the script does not start, check the loader log for a missing library or unsupported API.

## Credits

Original script by **Mayskiy**. Refactored and documented as **ChatScope Mobile**.
