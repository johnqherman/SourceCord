# SourceCord

![Build Release](https://github.com/johnqherman/sourcecord/actions/workflows/build-release.yml/badge.svg)
![License](https://img.shields.io/github/license/johnqherman/SourceCord)
![Latest Release](https://img.shields.io/github/v/release/johnqherman/SourceCord)

## Overview

A SourceMod plugin that syncs chat between your Source Engine server and Discord. Players can talk with Discord users directly from in-game, while Discord messages appear in chat with nicknames and role colors.

<p align="center">
  <img src="https://github.com/user-attachments/assets/7aa1282d-81d4-4bdd-824c-c934d4dd817d" alt="Side by Side"/>
  <br>
  <em>Image courtesy of boba (matchaland.net)</em>
</p>

## Features

- **Two-way chat sync**: Game ↔ Discord messages in real time
- **Mentions**: Handles user, role, and channel mentions seamlessly
- **Steam profile integration**: Player avatars and steamID3s for ease of moderation 
- **Server event logs**: Join/leave notifications for players
- **Caching system**: Fast lookups for avatars, nicknames, role colors, etc. 

## Requirements

- **SourceMod**: Version 1.11 or higher
- **RipExt Extension**: For HTTP requests to Discord API
- **Discord Bot**: Bot token with appropriate permissions
- **Steam API Key**: For fetching player profile information

## Installation

1. Install the [RipExt](https://forums.alliedmods.net/showthread.php?t=298024) extension on your server
2. Download the latest `sourcecord.smx` from releases
3. Place `sourcecord.smx` in `addons/sourcemod/plugins/`
4. Load the plugin with `sm plugins load sourcecord` (it will auto-create both config files)
5. Edit `addons/sourcemod/configs/sourcecord.cfg` with your credentials (see configuration section)
6. Restart the plugin with `sm plugins reload sourcecord`

## Configuration

### 1. Operational Settings

On first load, the plugin creates `cfg/sourcemod/sourcecord.cfg` with operational settings:

```cfg
sc_interval "1.0"              // Check Discord messages every x second(s)
sc_log_connections "1"         // Log player connections to Discord? (enabled by default)
sc_use_role_colors "1"         // Show Discord role colors in-game? (enabled by default)  
sc_use_nicknames "1"           // Use Discord server nicknames? (enabled by default)
sc_show_steam_id "1"           // Show steamID3 in Discord messages? (enabled by default)
sc_show_discord_prefix "1"     // Show [Discord] prefix in chat messages? (enabled by default)
sc_discord_color "5865F2"      // Hex color code for Discord usernames (blurple by default)
```

### 2. Credentials Setup

The plugin will also create `addons/sourcemod/configs/sourcecord.cfg` if it doesn't exist.

**Edit the config file** with your sensitive credentials:

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

### Configuration Variables (Console/CVars)

| ConVar | Description | Default | Range |
|--------|-------------|---------|-------|
| `sc_interval` | Discord check interval (seconds) | 1.0 | 1.0 - 10.0 |
| `sc_log_connections` | Log player connect/disconnects | 1 | 0 - 1 |
| `sc_use_role_colors` | Use Discord role colors for usernames | 1 | 0 - 1 |
| `sc_use_nicknames` | Use Discord server nicknames instead of global usernames | 1 | 0 - 1 |
| `sc_show_steam_id` | Show Steam ID in Discord messages | 1 | 0 - 1 |
| `sc_show_discord_prefix` | Show [Discord] prefix in chat messages | 1 | 0 - 1 |
| `sc_discord_color` | Hex color code for Discord usernames (without # prefix) | "5865F2" | 6-char hex |
| `sc_config_file` | Config filename (without .cfg) - console only | "sourcecord" | - |

### Credentials Configuration (KeyValues Config File)

| Setting | Description | Location |
|---------|-------------|----------|
| `Discord.bot_token` | Discord Bot token | `configs/sourcecord.cfg` |
| `Discord.channel_id` | Discord channel ID | `configs/sourcecord.cfg` |
| `Discord.guild_id` | Discord guild/server ID | `configs/sourcecord.cfg` |
| `Discord.webhook_url` | Discord Webhook URL | `configs/sourcecord.cfg` |
| `Steam.api_key` | Steam API key | `configs/sourcecord.cfg` |

## Customization Options

### Steam ID Display
Control whether Steam IDs appear in Discord messages:
- **Enabled** (`sc_show_steam_id 1`): "PlayerName [U:1:123456789]"
- **Disabled** (`sc_show_steam_id 0`): "PlayerName"

### Discord Prefix
Control whether the `[Discord]` prefix appears in game chat:
- **Enabled** (`sc_show_discord_prefix 1`): "[Discord] Username: message"
- **Disabled** (`sc_show_discord_prefix 0`): "Username: message"

### Discord Username Color
Customize the color of Discord usernames in game chat using hex codes:
- **Default**: `sc_discord_color "5865F2"` (Discord blurple)
- **Custom examples**: 
  - `sc_discord_color "FF0000"` (red)
  - `sc_discord_color "00FF00"` (green)
  - `sc_discord_color "00FFFF"` (blue)

> **Note**: When Discord role colors are enabled (`sc_use_role_colors 1`), user role colors take precedence over `sc_discord_color`.

## Discord Setup

SourceCord requires **both** a bot token and a webhook URL.

- **Bot Token**: Lets the plugin read messages and fetch user/role/channel data
- **Webhook URL**: Sends game events and messages to Discord with custom names/avatars

You'll set up both in the steps below.

### Bot Setup

#### Step 1: Create Bot and Get Token

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application and bot
3. Copy the bot token and add it to your `configs/sourcecord.cfg` file as `bot_token`

#### Step 2: Enable Required Bot Intents

1. In the Discord Developer Portal, go to your bot's **Bot** settings page
2. Scroll down to **Privileged Gateway Intents**
3. Enable these intents:
   - **Message Content Intent**: Required to read the actual content of Discord messages
   - **Server Members Intent**: Required for fetching member nicknames and role information
4. Save changes

#### Step 3: Invite Bot to Your Server

**Required Permissions**:

- **View Channels**: Needed to see the configured channel and resolve mentions
- **Read Message History**: Needed to fetch/catch up on messages

**Bot Invitation URL**:

Use this URL to invite your bot with the required permissions (replace `<YOUR_BOT_CLIENT_ID>`):

```
https://discord.com/api/oauth2/authorize?client_id=<YOUR_BOT_CLIENT_ID>&permissions=66560&scope=bot
```

> ⚠️ This only sets permissions - you also need to enable the required intents in Step 2.

### Webhook Setup

1. In your Discord channel, go to Settings → Integrations → Webhooks
2. Create a new webhook
3. Copy the webhook URL and add it to your `configs/sourcecord.cfg` file as `webhook_url`

## Getting Discord IDs

- **Channel ID**: Right-click the channel → **Copy ID** (add as `channel_id` in config)
- **Guild ID**: Right-click the server name → **Copy ID** (add as `guild_id` in config)
- Enable **Developer Mode** in Discord settings to access these options

## Steam API Key

1. Generate a Steam API key from the [Steam Web API](https://steamcommunity.com/dev/apikey)
2. Add it to `configs/sourcecord.cfg` file as `api_key`

## Usage

SourceCord operates **automatically** once configured - no commands or player interaction required.

## Building from Source

### Prerequisites

- SourceMod compiler (`spcomp`)
- RipExt includes

### Compilation

```bash
# Clone repository
git clone https://github.com/johnqherman/SourceCord.git
cd SourceCord

# Install dependencies and compile (GitHub Actions method)
./scripts/get_version.sh  # Get current version
spcomp -iinclude sourcecord.sp  # Compile
```
