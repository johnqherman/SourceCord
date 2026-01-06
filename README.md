# SourceCord

![Build Release](https://github.com/johnqherman/sourcecord/actions/workflows/build-release.yml/badge.svg)
![License](https://img.shields.io/github/license/johnqherman/SourceCord)
![Latest Release](https://img.shields.io/github/v/release/johnqherman/SourceCord)

## Overview

A SourceMod plugin that syncs chat between your Source Engine server and Discord.

Players can talk with Discord users directly from in-game, while Discord messages appear in chat with nicknames and role colors.

<p align="center">
  <img src="https://github.com/user-attachments/assets/7aa1282d-81d4-4bdd-824c-c934d4dd817d" alt="Side by Side"/>
  <br>
  <em>Images courtesy of <a href="https://github.com/bobatealee">boba</a></em>
</p>

## Features

- **Two-way chat sync**: Game ↔ Discord messages in real time
- **Mentions**: Handles user, role, and channel mentions seamlessly
- **Steam profile integration**: Player avatars and configurable Steam ID formats
- **Server event logs**: Join/leave notifications for players
- **Caching system**: Fast lookups for avatars, nicknames, role colors, etc.

## Game Compatibility

| Game                             | Status          | Notes                                     |
| -------------------------------- | --------------- | ----------------------------------------- |
| Team Fortress 2                  | ✅ Tested       | Designed for TF2, works flawlessly        |
| Half-Life 2: Deathmatch          | ✅ Tested       | Includes any mod based on Source SDK 2013 |
| Counter-Strike: Source           | ✅ Supported    | 64-bit only                               |
| Left 4 Dead 2                    | ✅ Supported    | 64-bit only                               |
| Insurgency                       | ✅ Supported    | 64-bit only                               |
| Counter-Strike: Global Offensive | ⚠️ Legacy       | Deprecated; last CS:GO server builds only |
| Day of Defeat: Source            | ❌ Unsupported  | Incompatible with SourceMod 1.12+         |
| Garry's Mod                      | ❌ Incompatible | Not officially supported                  |

> SourceCord should work with any Source Engine game that supports SourceMod 1.12+.
> <br>
> If you encounter issues, please file a [bug report](https://github.com/johnqherman/SourceCord/issues/new?template=bug_report.yml).

## Requirements

- **SourceMod**: Version 1.12 or higher
- **REST in Pawn**: For HTTP requests to Discord API
- **Discord Bot**: Bot token with appropriate permissions
- **Steam API Key**: For fetching player profile information

## Installation

1. Install the [REST in Pawn](https://forums.alliedmods.net/showthread.php?t=298024) extension on your server
2. Download the latest `sourcecord.smx` from [releases](https://github.com/johnqherman/SourceCord/releases/latest)
3. Place `sourcecord.smx` in `addons/sourcemod/plugins/`
4. Load the plugin with `sm plugins load sourcecord` (it will auto-create both config files)
5. Edit `cfg/sourcemod/sourcecord.cfg` to set your preferred settings
6. Edit `addons/sourcemod/configs/sourcecord.cfg` to add your credentials
7. Restart the plugin with `sm plugins reload sourcecord`

## Configuration

### 1. Settings

On first load, the plugin creates `cfg/sourcemod/sourcecord.cfg` with operational settings.

**Edit this file** to set your preferred settings:

```cfg
sc_interval "1.0"              // Check Discord messages every x second(s)
sc_log_connections "1"         // Log player connections (0 = off, 1 = basic, 2 = with IP)
sc_use_role_colors "1"         // Show Discord role colors in-game? (enabled by default)
sc_use_nicknames "1"           // Use Discord server nicknames? (enabled by default)
sc_show_steam_id "1"           // Show Steam ID format (0 = off, 1 = steamID3, 2 = steamID)
sc_show_discord_prefix "1"     // Show [Discord] prefix in chat messages? (enabled by default)
sc_discord_color "5865F2"      // Hex color for Discord usernames in game chat (blurple by default)
```

### 2. Credentials File

The plugin will also generate `addons/sourcemod/configs/sourcecord.cfg` to store your credentials.

```cfg
"SourceCord"
{
    "Discord"
    {
        "bot_token"     ""  // Discord Bot token
        "channel_id"    ""  // Discord channel ID
        "guild_id"      ""  // Discord guild/server ID
        "webhook_url"   ""  // Discord Webhook URL
    }

    "Steam"
    {
        "api_key"       ""  // Steam API key
    }
}
```

## Discord Setup

SourceCord requires **both** a bot token and a webhook URL.

- **Bot Token**: Lets the plugin read messages and fetch user/role/channel data
- **Webhook URL**: Sends game events and messages to Discord with custom names/avatars

You'll set up both in the steps below.

### Bot Setup

#### Step 1: Create Bot and Get Token

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application and bot user
3. Copy the bot token and add it to your `configs/sourcecord.cfg` file as `bot_token`

#### Step 2: Enable Required Bot Intents

1. In the Discord Developer Portal, go to your bot's **Bot** settings page
2. Scroll down to **Privileged Gateway Intents**
3. Enable these intents:

- **Server Members Intent**: Required for fetching member nicknames and role information.
- **Message Content Intent**: Required to read the actual content of Discord messages.

4. Save changes

  <img width="614" height="186" src="https://github.com/user-attachments/assets/08214ddf-2cbf-4451-bf0e-88010f3f02a6" />

#### Step 3: Invite Bot to Your Server

**Required Permissions**:

- **View Channels**: Needed to see the configured channel and resolve mentions
- **Read Message History**: Needed to fetch/catch up on messages

**Bot Invitation URL**:

Use this URL to invite your bot to your server with the required permissions (replace `<YOUR_BOT_CLIENT_ID>`):

```
https://discord.com/api/oauth2/authorize?client_id=<YOUR_BOT_CLIENT_ID>&permissions=66560&scope=bot
```

> ⚠️ This only sets permissions - you also need to enable the required intents in Step 2.

### Webhook Setup

1. In your Discord channel, go to **Edit Channel → Integrations → Webhooks**
2. Create a new webhook (+ optionally set a default avatar)
3. Copy the webhook URL and add it to `configs/sourcecord.cfg` as `webhook_url`

### Getting Discord IDs

- **Channel ID**: Right-click channel → **Copy Channel ID** (add to `configs/sourcecord.cfg` as `channel_id`)
- **Guild ID**: Right-click server name → **Copy Server ID** (add to `configs/sourcecord.cfg` as `guild_id`)
- Enable **Developer Mode** in Discord settings to access these options

## Steam API Key

1. Generate a Steam API key from the [Steam Web API](https://steamcommunity.com/dev/apikey)
2. Add it to `configs/sourcecord.cfg` as `api_key`

## Customization Options

Edit these settings in `cfg/sourcemod/sourcecord.cfg` to customize SourceCord to your liking.

### Steam ID Display

Control Steam ID format in both Discord messages and connection logs:

- **Disabled** (`sc_show_steam_id 0`):

<img src="https://github.com/user-attachments/assets/b5e24967-371d-4afe-8d15-8a58f6ed2cbb" style="margin-top: -10px; margin-bottom: -10px;"></img>

- **SteamID3 Format** (`sc_show_steam_id 1`):

<img src="https://github.com/user-attachments/assets/04070f11-598e-4d2e-82fa-c21eb32c59f7" style="margin-top: -10px; margin-bottom: -10px;"></img>

- **SteamID Format** (`sc_show_steam_id 2`):

<img src="https://github.com/user-attachments/assets/454afb93-a8d4-4c34-a4d0-d64f7de4aac1" style="margin-top: -10px; margin-bottom: -10px;"></img>

> ⚠️**Note**: Steam IDs will appear in chat messages _and_ connection messages when enabled.

### Connection Logging Options

Control what information appears in connect/disconnect messages:

- **Disabled** (`sc_log_connections 0`):
  - No connect/disconnect messages sent to Discord

- **Basic Logging** (`sc_log_connections 1`):

<img src="https://github.com/user-attachments/assets/2d4b4e55-b8b6-41f6-b764-0d9402bda87e" style="margin-top: -10px; margin-bottom: -10px;"></img>

- **IP Logging** (`sc_log_connections 2`):

<img src="https://github.com/user-attachments/assets/4fa6c66b-5dff-4e9b-a2db-86f7d5c8e5bb" style="margin-top: -10px; margin-bottom: -10px;"></img>

### Discord Prefix

Control whether the `[Discord]` prefix appears in game chat:

- **Enabled** (`sc_show_discord_prefix 1`):

<img src="https://github.com/user-attachments/assets/13137d50-95f8-4a34-9df1-afd090e8017a" style="margin-top: -10px; margin-bottom: -10px;"></img>

- **Disabled** (`sc_show_discord_prefix 0`):

<img src="https://github.com/user-attachments/assets/57198244-f98c-44fe-a17e-1712003adfa2" style="margin-top:-10px; margin-bottom: -10px;"></img>

### Discord Username Color

Customize the default color of Discord usernames in game chat:

- **Default**: (`sc_discord_color "5865F2"`):

<img src="https://github.com/user-attachments/assets/41d93727-3cdf-41de-b37f-00ea2bbef75d" style="margin-top:-10px; margin-bottom: -10px;"></img>

- **Custom**: (`sc_discord_color "EF0988"`):

<img src="https://github.com/user-attachments/assets/ddb63c07-ace9-40a9-a052-d874ccd1cf6f" style="margin-top: -10px; margin-bottom: -10px;"></img>

> ⚠️**Note**: When Discord role colors are enabled (`sc_use_role_colors 1`), user role colors take precedence over `sc_discord_color`.

## Building from Source

### Prerequisites

- SourceMod compiler (`spcomp`)
- REST in Pawn includes

### Compilation

```bash
# Clone repository
git clone https://github.com/johnqherman/SourceCord.git
cd SourceCord

# Copy files to SourceMod's scripting directory
cp sourcecord.sp /path/to/addons/sourcemod/scripting/
cp -r sourcecord/ /path/to/addons/sourcemod/scripting/

# Compile the plugin
cd /path/to/addons/sourcemod/scripting/
spcomp sourcecord.sp
```
