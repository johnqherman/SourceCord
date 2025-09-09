# SourceCord

![Build Release](https://github.com/johnqherman/sourcecord/actions/workflows/build-release.yml/badge.svg)

A Discord chat integration plugin for Source Engine games using SourceMod.

## Overview

Enables realtime bi-directional chat communication between your Source Engine game and Discord server. Players can chat with Discord users directly from in-game, and Discord messages appear in game chat with proper formatting and role colors.

<p align="center">
  <img src="https://via.assets.so/img.jpg?w=900&h=350&bg=1f2937&text=IN-GAME+%7C+DISCORD&fontColor=6b7280&f=png" alt="Placeholder"/>
</p>

## Features

- **Bi-directional chat**: Game → Discord + Discord → Game message relay
- **Discord role colors**: Display usernames with their highest Discord role colors in-game
- **Steam profile integration**: Fetch player avatars and profile info for easy moderation
- **Easy Discord setup**: Simple configuration with bot token and webhook URL
- **Configurable connection logging**: Optional player join/leave notifications
- **Reliable message delivery**: Optimized system ensures all messages get through
- **Automatic error recovery**: Handles network issues and Discord outages gracefully

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

The plugin automatically generates a configuration file at `cfg/sourcemod/sourcecord.cfg` on first load with default values.

Edit this file and add your Discord and Steam API credentials:

```cfg
// Discord Bot Configuration - ADD YOUR VALUES HERE
sc_bot_token ""          // Your Discord Bot token
sc_channel_id ""         // Your Discord channel ID  
sc_guild_id ""           // Your Discord guild/server ID

// Optional: Webhook URL 
sc_webhook_url ""        // Your Discord Webhook URL

// Steam API Integration
sc_steam_key ""          // Your Steam API key

// Plugin Behavior (defaults shown)
sc_interval "1.0"        // Check Discord messages every 1 second
sc_log_connections "0"   // Log player connections to Discord (disabled by default)
sc_use_role_colors "0"   // Show Discord role colors in-game (disabled by default)  
sc_use_nicknames "1"     // Use Discord server nicknames (enabled by default)
```

**Note**: The `sc_config_file` ConVar is console-only and doesn't appear in the generated config file.

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

SourceCord needs **both** a bot token and webhook URL to work.

- **Bot Token**: Lets the plugin read Discord messages and get user/role/channel information
- **Webhook URL**: Lets the plugin send game events/messages to Discord with custom names and avatars

The bot token reads from Discord, while the webhook sends to Discord with custom player identities. You'll set up both in the steps below.

### Bot Setup

#### Step 1: Create Bot and Get Token

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create a new application and bot
3. Copy the bot token for `sc_bot_token`

#### Step 2: Enable Required Bot Intents

1. In the Discord Developer Portal, go to your bot's **Bot** settings page
2. Scroll down to **Privileged Gateway Intents**
3. Enable these intents:
   - **Message Content Intent**: Required to read the actual content of Discord messages
   - **Server Members Intent**: Required for fetching member nicknames and role information
4. Save changes

#### Step 3: Invite Bot to Your Server

**Discord Bot Permissions** (configured via invitation URL):

**Essential Permissions** (SourceCord will not work without these):
- **View Channels**: Required to see the configured channel and resolve channel mentions in messages
- **Read Message History**: Required to fetch Discord messages and catch up on missed messages

**Feature-Specific Permissions**:
- **View Server**: Required to fetch role colors and server nicknames
- Bot must have access to view roles if `sc_use_role_colors` is enabled
- Bot must have access to member information if `sc_use_nicknames` is enabled

**Bot Invitation URL**:

Use this URL to invite your bot with the required permissions (replace `<YOUR_BOT_CLIENT_ID>`):

```
https://discord.com/api/oauth2/authorize?client_id=<YOUR_BOT_CLIENT_ID>&permissions=66560&scope=bot
```

**Important**: The invitation URL only handles permissions - you also need to enable the required intents in Step 2 above.

### Webhook Setup

1. In your Discord channel, go to Settings → Integrations → Webhooks
2. Create a new webhook
3. Copy the webhook URL for `sc_webhook_url`

## Getting Discord IDs

- **Channel ID**: Right-click your channel → Copy ID
- **Guild ID**: Right-click your server name → Copy ID
- Enable Developer Mode in Discord settings to see these options

## Steam API Key

Get your Steam API key from [Steam Web API](https://steamcommunity.com/dev/apikey) and add it to `sc_steam_key`.

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