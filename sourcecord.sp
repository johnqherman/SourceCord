#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ripext>

#define PLUGIN_VERSION "1.1.0"

#include "sourcecord/globals.sp"
#include "sourcecord/config.sp"
#include "sourcecord/discord/api.sp"
#include "sourcecord/cache.sp"
#include "sourcecord/utils.sp"
#include "sourcecord/chat_integration.sp"
#include "sourcecord/webhook.sp"
#include "sourcecord/discord/fetch.sp"
#include "sourcecord/discord/mentions.sp"
#include "sourcecord/discord/users.sp"

public Plugin myinfo =
{
	name = "SourceCord",
	author = "johnqherman",
	description = "Discord chat integration for Source Engine games",
	version = PLUGIN_VERSION,
	url = "https://github.com/johnqherman/SourceCord/",
};


public void OnPluginStart() {
	InitializeConfig();
	InitializeCaches();
	InitializeChatIntegration();
}


public void OnConfigsExecuted() {
	LoadCredentials();
	CacheSettings();
	StartTimer();
}


public void OnPluginEnd() {
	CleanupCaches();
}
