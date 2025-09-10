# SourceCord

![Build Release](https://github.com/johnqherman/sourcecord/actions/workflows/build-release.yml/badge.svg)
![License](https://img.shields.io/github/license/johnqherman/SourceCord)
![Latest Release](https://img.shields.io/github/v/release/johnqherman/SourceCord)

## Overview

Enables real-time, two-way chat between your Source Engine game and a Discord server. Players can chat with Discord users directly from in-game, while Discord messages appear in the game chat with proper formatting and role colors.

<p align="center">
  <img src="https://github.com/user-attachments/assets/b53e7efe-bf00-45da-9de2-3798fc393c19" alt="Side by Side"/>
</p>

## Features

- **Two-way chat sync**: Relays messages both Game → Discord and Discord → Game
- **Discord role colors**: Shows usernames in-game with their highest role color
- **Steam profile integration**: Fetches players’ avatars and SteamID3s for moderation
- **Configurable logging**: Optional join/leave notifications for players
- **Automatic recovery**: Handles network issues and Discord outages smoothly

## Requirements

- **SourceMod**: Version 1.11 or higher
- **RipExt Extension**: For HTTP requests to Discord API
- **Discord Bot**: Bot token with appropriate permissions
- **Steam API Key**: For fetching player profile information

## Installation

1. Install the [RipExt](https://forums.alliedmods.net/showthread.php?t=298024) extension on your server
2. Download the latest `sourcecord.smx` from releases
3. Place `sourcecord.smx` in `addons/sourcemod/plugins/`
4. Configure the plugin (see configuration section)
5. Restart your server or use `sm plugins load sourcecord`

## Configuration

On first load, the plugin automatically creates a configuration file at `cfg/sourcemod/sourcecord.cfg` with default settings.

Edit this file and add your Discord and Steam API credentials:

```cfg
// Discord
sc_bot_token ""          // Your Discord Bot token
sc_channel_id ""         // Your Discord channel ID  
sc_guild_id ""           // Your Discord guild/server ID
sc_webhook_url ""        // Your Discord Webhook URL

// Steam
sc_steam_key ""          // Your Steam API key

// Plugin Behavior
sc_interval "1.0"        // Check Discord messages every 1 second
sc_log_connections "0"   // Log player connections to Discord (disabled by default)
sc_use_role_colors "0"   // Show Discord role colors in-game (disabled by default)  
sc_use_nicknames "1"     // Use Discord server nicknames (enabled by default)
```

**Note**: The `sc_config_file` ConVar is console-only and won’t appear in the generated config file.

### Configuration Variables

| ConVar | Description | Default | Range |
|--------|-------------|---------|-------|
| `sc_bot_token` | Discord Bot token | "" | - |
| `sc_channel_id` | Discord channel ID | "" | - |
| `sc_guild_id` | Discord guild/server ID | "" | - |
| `sc_webhook_url` | Discord Webhook URL | "" | - |
| `sc_steam_key` | Steam API key | "" | - |
| `sc_interval` | Discord check interval (seconds) | 1.0 | 0.1 - 10.0 |
| `sc_log_connections` | Log player connect/disconnects | 0 | 0 - 1 |
| `sc_use_role_colors` | Use Discord role colors for usernames | 0 | 0 - 1 |
| `sc_use_nicknames` | Use Discord server nicknames instead of global usernames | 1 | 0 - 1 |
| `sc_config_file` | Config filename (without .cfg) - console only | "sourcecord" | - |

## Discord Integration Setup

SourceCord requires **both** a bot token and a webhook URL.

- **Bot Token**: Lets the plugin read messages and fetch user/role/channel data
- **Webhook URL**: Sends game events and messages to Discord with custom names/avatars

You'll set up both in the steps below.

### Bot Setup

#### Step 1: Create Bot and Get Token

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application and bot
3. Copy the bot token and set it as `sc_bot_token`

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

⚠️ This only sets permissions - you also need to enable the required intents in Step 2.

### Webhook Setup

1. In your Discord channel, go to Settings → Integrations → Webhooks
2. Create a new webhook
3. Copy the webhook URL and set it as `sc_webhook_url`

## Getting Discord IDs

- **Channel ID**: Right-click the channel → **Copy ID**
- **Guild ID**: Right-click the server name → **Copy ID**
- Enable **Developer Mode** in Discord settings to access these options

## Steam API Key

Generate a Steam API key from the [Steam Web API](https://steamcommunity.com/dev/apikey) and set it in `sc_steam_key`.

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
