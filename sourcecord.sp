#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ripext>

#define PLUGIN_VERSION "1.1.0+build.1"

#include "sourcecord/globals.sp"
#include "sourcecord/emoji_data.sp"
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
	if (CheckConfigFileChange()) {
		CreateTimer(0.1, Timer_DelayedInit);
	} else {
		CacheSettings();
		LoadCredentials();
		StartTimer();
	}
}


Action Timer_DelayedInit(Handle timer) {
	CacheSettings();
	LoadCredentials();
	StartTimer();
	return Plugin_Stop;
}


public void OnMapStart() {
	LogMapChange();
}


public void OnPluginEnd() {
	CleanupCaches();
}
