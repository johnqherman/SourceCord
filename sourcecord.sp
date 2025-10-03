#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ripext>

#define PLUGIN_VERSION "1.0.7"

#define AVATAR_CACHE_TTL 1800.0 // 30 minutes
#define DISCORD_NICK_TTL 1800.0 // 30 minutes
#define DISCORD_COLOR_TTL 3600.0 // 1 hour
#define DISCORD_LONG_TTL 86400.0 // 24 hours
#define CLEANUP_THRESHOLD 100

#define DISCORD_API_BASE_URL "https://discord.com/api/v10"
#define DISCORD_DEFAULT_COLOR "5865F2"
#define STEAM_API_BASE_URL "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002"

#define DISCORD_PREFIX_COLOR "\x075865F2"
#define CHAT_COLOR_RESET "\x01"
#define MAX_RETRY_DELAY 60.0
#define MAX_BATCH_SIZE 5

public Plugin myinfo =
{
	name = "SourceCord",
	author = "sharkobarko",
	description = "Discord chat integration for Source Engine games",
	version = PLUGIN_VERSION,
	url = "https://github.com/johnqherman/SourceCord/",
};

// convars
ConVar g_cvConfigFile;
ConVar g_cvUpdateInterval;
ConVar g_cvLogConnections;
ConVar g_cvUseRoleColors;
ConVar g_cvUseNicknames;
ConVar g_cvShowSteamId;
ConVar g_cvShowDiscordPrefix;
ConVar g_cvDiscordColor;

// settings
float g_fUpdateInterval;
int g_iLogConnections;
bool g_bUseRoleColors;
bool g_bUseNicknames;
int g_iShowSteamId;
bool g_bShowDiscordPrefix;
char g_sDiscordColor[8];

// credentials
char g_sBotToken[128];
char g_sChannelId[32];
char g_sGuildId[32];
char g_sWebhookUrl[256];
char g_sSteamApiKey[64];

// discord state
char g_sLastMessageId[32];
Handle g_hDiscordTimer;

// error handling
int g_iFailedRequests;
float g_fNextRetryTime;

// cache
StringMap g_hUserColorCache;
StringMap g_hUserNameCache;
StringMap g_hUserNickCache;
StringMap g_hUserAvatarCache;
StringMap g_hChannelNameCache;
StringMap g_hRoleNameCache;

// message queuing
ArrayList g_hMessageQueue;
StringMap g_hProcessedMessages;
ArrayList g_hMessageIdOrder;

// team chat tracking
bool g_bClientTeamChat[MAXPLAYERS + 1];

// connection state tracking
bool g_bClientConnected[MAXPLAYERS + 1];

public void OnPluginStart() {
	g_cvConfigFile = CreateConVar("sc_config_file", "sourcecord", "Config filename (without .cfg)", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvUpdateInterval = CreateConVar("sc_interval", "1.0", "Discord check interval (seconds)", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	g_cvLogConnections = CreateConVar("sc_log_connections", "1", "Log player connect/disconnects (off, basic, with IP)", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvUseRoleColors = CreateConVar("sc_use_role_colors", "1", "Use Discord role colors for usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvUseNicknames = CreateConVar("sc_use_nicknames", "1", "Use Discord server nicknames instead of global usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvShowSteamId = CreateConVar("sc_show_steam_id", "1", "Show Steam ID in Discord messages (off, steamID3, steamID)", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvShowDiscordPrefix = CreateConVar("sc_show_discord_prefix", "1", "Show [Discord] prefix in chat messages", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDiscordColor = CreateConVar("sc_discord_color", DISCORD_DEFAULT_COLOR, "Hex color code for Discord usernames (without # prefix)", FCVAR_NOTIFY);

	// init caches
	g_hUserColorCache = new StringMap();
	g_hUserNameCache = new StringMap();
	g_hUserNickCache = new StringMap();
	g_hUserAvatarCache = new StringMap();
	g_hChannelNameCache = new StringMap();
	g_hRoleNameCache = new StringMap();

	// init message queue and processing cache
	g_hMessageQueue = new ArrayList(ByteCountToCells(512));
	g_hProcessedMessages = new StringMap();
	g_hMessageIdOrder = new ArrayList(ByteCountToCells(32));
	g_iFailedRequests = 0;
	g_fNextRetryTime = 0.0;

	// init connection states
	for (int i = 1; i <= MaxClients; i++) {
		g_bClientConnected[i] = false;
		g_bClientTeamChat[i] = false;
	}

	HookEvent("player_say", Event_PlayerSay);
	HookEvent("player_activate", Event_PlayerConnect);
	HookEvent("player_disconnect", Event_PlayerDisconnect);

	g_cvConfigFile.AddChangeHook(OnConVarChanged);
	g_cvUpdateInterval.AddChangeHook(OnConVarChanged);
	g_cvLogConnections.AddChangeHook(OnConVarChanged);
	g_cvUseRoleColors.AddChangeHook(OnConVarChanged);
	g_cvUseNicknames.AddChangeHook(OnConVarChanged);
	g_cvShowSteamId.AddChangeHook(OnConVarChanged);
	g_cvShowDiscordPrefix.AddChangeHook(OnConVarChanged);
	g_cvDiscordColor.AddChangeHook(OnConVarChanged);

	// create operational config if it doesn't exist
	char configFile[64];
	g_cvConfigFile.GetString(configFile, sizeof configFile);
	AutoExecConfig(true, configFile);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_bClientTeamChat[client] = false;

	if (StrEqual(command, "say_team") || StrEqual(command, "say_squad")) {
		g_bClientTeamChat[client] = true;
	}

	return Plugin_Continue;
}

public void OnConfigsExecuted() {
	char configFile[64];
	g_cvConfigFile.GetString(configFile, sizeof configFile);
	if (strlen(configFile) > 0 && !StrEqual(configFile, "sourcecord")) {
		ServerCommand("exec sourcemod/%s.cfg", configFile);
	}

	LoadSensitiveCredentials();
	LoadOperationalSettings();
	StartTimer();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvConfigFile) {
		ServerCommand("exec sourcemod/%s.cfg", newValue);
		return ;
	}

	LoadOperationalSettings();

	if (convar == g_cvUpdateInterval) {
		StartTimer();
	}
}

void LoadOperationalSettings() {
	g_fUpdateInterval = g_cvUpdateInterval.FloatValue;
	g_iLogConnections = g_cvLogConnections.IntValue;
	g_bUseRoleColors = g_cvUseRoleColors.BoolValue;
	g_bUseNicknames = g_cvUseNicknames.BoolValue;
	g_iShowSteamId = g_cvShowSteamId.IntValue;
	g_bShowDiscordPrefix = g_cvShowDiscordPrefix.BoolValue;
	g_cvDiscordColor.GetString(g_sDiscordColor, sizeof g_sDiscordColor);

	if (!IsValidHexColor(g_sDiscordColor)) {
		LogMessage("Invalid hex color format '%s'", g_sDiscordColor);
		strcopy(g_sDiscordColor, sizeof g_sDiscordColor, DISCORD_DEFAULT_COLOR);
	}
}

void LoadSensitiveCredentials() {
	char configFile[64];
	g_cvConfigFile.GetString(configFile, sizeof configFile);

	char configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof configPath, "configs/%s.cfg", configFile);

	KeyValues kv = new KeyValues("SourceCord");
	if (!kv.ImportFromFile(configPath)) {
		LogError("Failed to load configuration file: %s", configPath);

		CreateExampleConfig(configPath);

		delete kv;
		return ;
	}

	if (kv.JumpToKey("Discord", false)) {
		kv.GetString("bot_token", g_sBotToken, sizeof g_sBotToken, "");
		kv.GetString("channel_id", g_sChannelId, sizeof g_sChannelId, "");
		kv.GetString("guild_id", g_sGuildId, sizeof g_sGuildId, "");
		kv.GetString("webhook_url", g_sWebhookUrl, sizeof g_sWebhookUrl, "");
		kv.GoBack();
	}

	if (kv.JumpToKey("Steam", false)) {
		kv.GetString("api_key", g_sSteamApiKey, sizeof g_sSteamApiKey, "");
		kv.GoBack();
	}

	delete kv;

	if (strlen(g_sBotToken) == 0) {
		LogError("Bot token not configured! Please set 'bot_token' in %s", configPath);
	}
	if (strlen(g_sChannelId) == 0) {
		LogError("Channel ID not configured! Please set 'channel_id' in %s", configPath);
	}

	LogMessage("Configuration loaded successfully from %s", configPath);
}

void CreateExampleConfig(const char[] configPath) {
	File file = OpenFile(configPath, "w");
	if (file == null) {
		LogError("Failed to create example config file at %s", configPath);
		return ;
	}

	file.WriteLine("\"SourceCord\"");
	file.WriteLine("{");
	file.WriteLine("    \"Discord\"");
	file.WriteLine("    {");
	file.WriteLine("        \"bot_token\"     \"\"  // Discord Bot token");
	file.WriteLine("        \"channel_id\"    \"\"  // Discord channel ID");
	file.WriteLine("        \"guild_id\"      \"\"  // Discord guild/server ID");
	file.WriteLine("        \"webhook_url\"   \"\"  // Discord Webhook URL");
	file.WriteLine("    }");
	file.WriteLine("    ");
	file.WriteLine("    \"Steam\"");
	file.WriteLine("    {");
	file.WriteLine("        \"api_key\"       \"\"  // Steam API key");
	file.WriteLine("    }");
	file.WriteLine("}");

	file.Close();
	LogMessage("Created example configuration file at %s", configPath);
	LogMessage("Please edit this file with your Discord bot token, webhook URL, and other credentials, then restart the plugin.");
}

void StartTimer() {
	LoadOperationalSettings();

	if (g_hDiscordTimer != null) {
		KillTimer(g_hDiscordTimer);
		g_hDiscordTimer = null;
	}

	if (strlen(g_sBotToken) > 0 && strlen(g_sChannelId) > 0) {
		g_hDiscordTimer = CreateTimer(g_fUpdateInterval, Timer_CheckDiscord, _, TIMER_REPEAT);
	}
}

HTTPRequest CreateDiscordAPIRequest(const char[] url) {
	HTTPRequest request = new HTTPRequest(url);

	char authHeader[256];
	Format(authHeader, sizeof authHeader, "Bot %s", g_sBotToken);
	request.SetHeader("Authorization", authHeader);

	char userAgent[64];
	Format(userAgent, sizeof userAgent, "SourceCord/%s", PLUGIN_VERSION);
	request.SetHeader("User-Agent", userAgent);

	return request;
}

HTTPRequest CreateSteamAPIRequest(const char[] url) {
	HTTPRequest request = new HTTPRequest(url);

	char userAgent[64];
	Format(userAgent, sizeof userAgent, "SourceCord/%s", PLUGIN_VERSION);
	request.SetHeader("User-Agent", userAgent);

	return request;
}

public Action Timer_CheckDiscord(Handle timer) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sChannelId) == 0) {
		return Plugin_Continue;
	}

	if (g_fNextRetryTime > 0.0 && GetGameTime() < g_fNextRetryTime) {
		return Plugin_Continue;
	}

	char url[256];
	if (strlen(g_sLastMessageId) > 0) {
		Format(url, sizeof url, "%s/channels/%s/messages?limit=1&after=%s", DISCORD_API_BASE_URL, g_sChannelId, g_sLastMessageId);
	}
	else {
		Format(url, sizeof url, "%s/channels/%s/messages?limit=1", DISCORD_API_BASE_URL, g_sChannelId);
	}

	HTTPRequest request = CreateDiscordAPIRequest(url);
	request.SetHeader("Accept", "application/json");

	request.Get(OnDiscordResponse, INVALID_HANDLE);

	return Plugin_Continue;
}

public void OnDiscordResponse(HTTPResponse response, any data) {
	if (response.Status != HTTPStatus_OK) {
		HandleDiscordError(response.Status);
		return ;
	}

	g_iFailedRequests = 0;
	g_fNextRetryTime = 0.0;

	if (response.Data == null) {
		return ;
	}

	JSONArray messages = view_as<JSONArray>(response.Data);
	if (messages == null || messages.Length == 0) {
		if (messages != null) {
			delete messages;
		}
		return ;
	}

	int messageCount = messages.Length;
	char latestMessageId[32];

	for(int i = messageCount - 1; i >= 0; i--) {
		JSONObject message = view_as<JSONObject>(messages.Get(i));
		if (message == null) {
			continue;
		}

		char messageId[32];
		message.GetString("id", messageId, sizeof messageId);

		bool alreadyProcessed;
		if (g_hProcessedMessages.GetValue(messageId, alreadyProcessed)) {
			delete message;
			continue;
		}

		g_hProcessedMessages.SetValue(messageId, true);
		g_hMessageIdOrder.PushString(messageId);
		strcopy(latestMessageId, sizeof latestMessageId, messageId);

		if (strlen(g_sLastMessageId) == 0) {
			delete message;
			continue;
		}

		JSONObject author = view_as<JSONObject>(message.Get("author"));
		if (author == null) {
			delete message;
			continue;
		}

		bool isBot = false;
		if (author.HasKey("bot")) {
			isBot = author.GetBool("bot");
		}

		if (isBot) {
			delete author;
			delete message;
			continue;
		}

		char username[64], content[512], userId[32];
		author.GetString("username", username, sizeof username);
		author.GetString("id", userId, sizeof userId);
		message.GetString("content", content, sizeof content);

		delete author;
		delete message;

		if (strlen(content) > 0) {
			QueueMessageForProcessing(userId, username, content);
		}
	}

	if (strlen(latestMessageId) > 0) {
		strcopy(g_sLastMessageId, sizeof g_sLastMessageId, latestMessageId);
	}

	delete messages;
	ProcessMessageQueue();

	static int cleanupCounter = 0;
	cleanupCounter++;

	if (cleanupCounter >= CLEANUP_THRESHOLD) {
		CleanupProcessedMessages();
		cleanupCounter = 0;
	}
}

void CleanupProcessedMessages() {
	if (g_hProcessedMessages.Size <= 512) {
		return ;
	}

	int currentSize = g_hProcessedMessages.Size;
	int entriesToRemove = currentSize - 512;

	for(int i = 0; i < entriesToRemove && g_hMessageIdOrder.Length > 0; i++) {
		char oldestId[32];
		g_hMessageIdOrder.GetString(0, oldestId, sizeof oldestId);
		g_hMessageIdOrder.Erase(0);
		g_hProcessedMessages.Remove(oldestId);
	}

	LogMessage("LRU cleanup completed (final size: %d)", g_hProcessedMessages.Size);
}

void HandleDiscordError(HTTPStatus status) {
	LogDiscordAPIError(status, "message fetching");

	g_iFailedRequests++;
	float backoffDelay = Pow(2.0, float(g_iFailedRequests - 1)) * g_fUpdateInterval;

	if (backoffDelay > MAX_RETRY_DELAY) {
		backoffDelay = MAX_RETRY_DELAY;
	}

	g_fNextRetryTime = GetGameTime() + backoffDelay;
	LogMessage("Discord retry scheduled in %.1f seconds (attempt %d)", backoffDelay, g_iFailedRequests);
}

void QueueMessageForProcessing(const char[] userId, const char[] username, const char[] content) {
	char messageData[512];
	Format(messageData, sizeof messageData, "%s|%s|%s", userId, username, content);
	g_hMessageQueue.PushString(messageData);
}

void ProcessMessageQueue() {
	int queueSize = g_hMessageQueue.Length;
	if (queueSize == 0) {
		return ;
	}

	int processCount = (queueSize > MAX_BATCH_SIZE) ? MAX_BATCH_SIZE : queueSize;

	for(int i = 0; i < processCount; i++) {
		char messageData[512];
		g_hMessageQueue.GetString(0, messageData, sizeof messageData);
		g_hMessageQueue.Erase(0);

		char parts[3][256];
		if (ExplodeString(messageData, "|", parts, sizeof parts, sizeof parts[] ) == 3) {
			ProcessDiscordMentions(parts[0], parts[1], parts[2]);
		}
	}

	if (g_hMessageQueue.Length > 0) {
		LogMessage("Message queue has %d remaining messages, will process next batch in %.1f seconds", g_hMessageQueue.Length, g_fUpdateInterval);
	}
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(client) || IsChatTrigger()) {
		return Plugin_Continue;
	}

	char message[256];
	event.GetString("text", message, sizeof message);

	if (strlen(message) == 0) {
		return Plugin_Continue;
	}

	bool isTeamChat = g_bClientTeamChat[client];

	SendToDiscord(client, message, isTeamChat);
	return Plugin_Continue;
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	if (g_iLogConnections == 0) {
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client <= 0 || client > MaxClients || !IsClientConnected(client)) {
		return Plugin_Continue;
	}

	if (IsFakeClient(client)) {
		return Plugin_Continue;
	}

	if (g_bClientConnected[client]) {
		return Plugin_Continue;
	}

	g_bClientConnected[client] = true;

	char playerName[64], escapedPlayerName[128], steamId[32], msg[256];
	GetClientName(client, playerName, sizeof playerName);
	EscapeUserContent(playerName, escapedPlayerName, sizeof escapedPlayerName);

	if (g_iShowSteamId == 1) {
		GetClientAuthId(client, AuthId_Steam3, steamId, sizeof steamId);
	} else if (g_iShowSteamId == 2) {
		char tempSteamId[32];
		GetClientAuthId(client, AuthId_Steam2, tempSteamId, sizeof tempSteamId);
		Format(steamId, sizeof steamId, "(%s)", tempSteamId);
	}

	if (g_iShowSteamId > 0 && StrEqual(steamId, "STEAM_ID_STOP_IGNORING_RETVALS")) {
		strcopy(steamId, sizeof steamId, "[Steam Offline]");
	}

	if (g_iLogConnections == 2 && g_iShowSteamId > 0) {
		char clientIP[32];
		GetClientIP(client, clientIP, sizeof clientIP);
		Format(msg, sizeof msg, "**%s** %s (%s) connected to the server", escapedPlayerName, steamId, clientIP);
	} else if (g_iLogConnections == 2) {
		char clientIP[32];
		GetClientIP(client, clientIP, sizeof clientIP);
		Format(msg, sizeof msg, "**%s** (%s) connected to the server", escapedPlayerName, clientIP);
	} else if (g_iShowSteamId > 0) {
		Format(msg, sizeof msg, "**%s** %s connected to the server", escapedPlayerName, steamId);
	} else {
		Format(msg, sizeof msg, "**%s** connected to the server", escapedPlayerName);
	}

	char serverName[64];
	GetServerName(serverName, sizeof serverName);
	SendWebhookWithEscaping(serverName, msg, "", false);

	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client > 0 && client <= MAXPLAYERS) {
		g_bClientTeamChat[client] = false;
	}

	if (g_iLogConnections == 0) {
		return Plugin_Continue;
	}

	if (client > 0 && IsFakeClient(client)) {
		return Plugin_Continue;
	}

	if (client <= 0 || client > MAXPLAYERS || !g_bClientConnected[client]) {
		return Plugin_Continue;
	}

	g_bClientConnected[client] = false;

	char playerName[64],
	     escapedPlayerName[128],
	     steamId[32],
	     reason[128],
	     escapedReason[256],
	     msg[512];
	event.GetString("name", playerName, sizeof playerName);
	event.GetString("reason", reason, sizeof reason);
	EscapeUserContent(playerName, escapedPlayerName, sizeof escapedPlayerName);
	EscapeUserContent(reason, escapedReason, sizeof escapedReason);

	if (g_iShowSteamId == 1) {
		GetClientAuthId(client, AuthId_Steam3, steamId, sizeof steamId);
	} else if (g_iShowSteamId == 2) {
		char tempSteamId[32];
		GetClientAuthId(client, AuthId_Steam2, tempSteamId, sizeof tempSteamId);
		Format(steamId, sizeof steamId, "(%s)", tempSteamId);
	}

	if (g_iShowSteamId > 0 && StrEqual(steamId, "STEAM_ID_STOP_IGNORING_RETVALS")) {
		strcopy(steamId, sizeof steamId, "[Steam Offline]");
	}

	if (g_iLogConnections == 2 && g_iShowSteamId > 0) {
		char clientIP[32];
		GetClientIP(client, clientIP, sizeof clientIP);
		Format(msg, sizeof msg, "**%s** %s (%s) disconnected (%s)", escapedPlayerName, steamId, clientIP, escapedReason);
	} else if (g_iLogConnections == 2) {
		char clientIP[32];
		GetClientIP(client, clientIP, sizeof clientIP);
		Format(msg, sizeof msg, "**%s** (%s) disconnected (%s)", escapedPlayerName, clientIP, escapedReason);
	} else if (g_iShowSteamId > 0) {
		Format(msg, sizeof msg, "**%s** %s disconnected (%s)", escapedPlayerName, steamId, escapedReason);
	} else {
		Format(msg, sizeof msg, "**%s** disconnected (%s)", escapedPlayerName, escapedReason);
	}

	char serverName[64];
	GetServerName(serverName, sizeof serverName);
	SendWebhookWithEscaping(serverName, msg, "", false);

	return Plugin_Continue;
}

void CopySubstring(const char[] source, int startPos, int length, char[] dest, int maxlen) {
	int copyLen = length;
	if (copyLen >= maxlen) {
		copyLen = maxlen - 1;
	}

	for(int i = 0; i < copyLen; i++) {
		dest[i] = source[startPos + i];
	}
	dest[copyLen] = '\0';
}

bool ProcessSingleUserMention(char[] messageContent, int maxContentLength, int mentionStartPosition, const char[] originalUserId, const char[] originalUsername, char[] userMentionPattern, char[] mentionedUserId) {
	int mentionEndPosition = StrContains(messageContent[mentionStartPosition], ">", false);
	if (mentionEndPosition == -1) {
		return false;
	}

	mentionEndPosition += mentionStartPosition;
	int userIdStartPosition = mentionStartPosition + 2;
	int userIdLength = mentionEndPosition - userIdStartPosition;

	if (userIdLength <= 0 || userIdLength >= 32) {
		return false;
	}

	CopySubstring(messageContent, userIdStartPosition, userIdLength, mentionedUserId, 32);

	char cachedDisplayName[64];
	if (GetCachedDiscordData(g_hUserNameCache, mentionedUserId, cachedDisplayName, sizeof cachedDisplayName, DISCORD_LONG_TTL)) {
		Format(userMentionPattern, 64, "<@%s>", mentionedUserId);
		char mentionReplacement[128];
		Format(mentionReplacement, sizeof mentionReplacement, "@%s", cachedDisplayName);
		ReplaceString(messageContent, maxContentLength, userMentionPattern, mentionReplacement, false);
		return true;
	}
	else {
		GetDiscordUserName(mentionedUserId, originalUserId, originalUsername, messageContent);
		return false;
	}
}

bool ProcessUserMentions(char[] content, int maxlen, const char[] userId, const char[] username) {
	int searchStart = 0, pos;
	char mentionPattern[32], mentionId[32];

	while((pos = StrContains(content[searchStart], "<@", false)) != -1) {
		int actualPos = searchStart + pos;

		if (actualPos + 2 < strlen(content) && content[actualPos + 2] == '&') {
			searchStart = actualPos + 1;
			continue;
		}

		if (!ProcessSingleUserMention(content, maxlen, actualPos, userId, username, mentionPattern, mentionId)) {
			return false;
		}
		searchStart = 0;
	}
	return true;
}

bool ProcessChannelMentions(char[] messageContent, int maxContentLength, const char[] originalUserId, const char[] originalUsername) {
	int searchStartPosition = 0, channelMentionPosition;
	char channelMentionPattern[32], mentionedChannelId[32];

	while((channelMentionPosition = StrContains(messageContent[searchStartPosition], "<#", false)) != -1) {
		int actualMentionPosition = searchStartPosition + channelMentionPosition;
		int mentionEndPosition = StrContains(messageContent[actualMentionPosition], ">", false);
		if (mentionEndPosition == -1) {
			break;
		}
		mentionEndPosition += actualMentionPosition;

		int channelIdStartPosition = actualMentionPosition + 2;
		int channelIdLength = mentionEndPosition - channelIdStartPosition;
		if (channelIdLength > 0 && channelIdLength < 32) {
			CopySubstring(messageContent, channelIdStartPosition, channelIdLength, mentionedChannelId, sizeof mentionedChannelId);

			char cachedChannelName[64];
			if (GetCachedDiscordData(g_hChannelNameCache, mentionedChannelId, cachedChannelName, sizeof cachedChannelName, DISCORD_LONG_TTL)) {
				Format(channelMentionPattern, sizeof channelMentionPattern, "<#%s>", mentionedChannelId);
				char mentionReplacement[128];
				Format(mentionReplacement, sizeof mentionReplacement, "#%s", cachedChannelName);
				ReplaceString(messageContent, maxContentLength, channelMentionPattern, mentionReplacement, false);
				searchStartPosition = 0;
			}
			else {
				GetDiscordChannelName(mentionedChannelId, originalUserId, originalUsername, messageContent);
				return false;
			}
		}
		else {
			searchStartPosition = mentionEndPosition + 1;
		}
	}
	return true;
}

bool ProcessRoleMentions(char[] messageContent, int maxContentLength, const char[] originalUserId, const char[] originalUsername) {
	int searchStartPosition = 0, roleMentionPosition;
	char roleMentionPattern[32], mentionedRoleId[32];

	while((roleMentionPosition = StrContains(messageContent[searchStartPosition], "<@&", false)) != -1) {
		int actualMentionPosition = searchStartPosition + roleMentionPosition;
		int mentionEndPosition = StrContains(messageContent[actualMentionPosition], ">", false);
		if (mentionEndPosition == -1) {
			break;
		}
		mentionEndPosition += actualMentionPosition;

		int roleIdStartPosition = actualMentionPosition + 3;
		int roleIdLength = mentionEndPosition - roleIdStartPosition;
		if (roleIdLength > 0 && roleIdLength < 32) {
			CopySubstring(messageContent, roleIdStartPosition, roleIdLength, mentionedRoleId, sizeof mentionedRoleId);

			char cachedRoleDisplayName[64];
			if (GetCachedDiscordData(g_hRoleNameCache, mentionedRoleId, cachedRoleDisplayName, sizeof cachedRoleDisplayName, DISCORD_LONG_TTL)) {
				Format(roleMentionPattern, sizeof roleMentionPattern, "<@&%s>", mentionedRoleId);
				char mentionReplacement[128];
				Format(mentionReplacement, sizeof mentionReplacement, "@%s", cachedRoleDisplayName);
				ReplaceString(messageContent, maxContentLength, roleMentionPattern, mentionReplacement, false);
				searchStartPosition = 0;
			}
			else {
				GetDiscordRoleName(mentionedRoleId, originalUserId, originalUsername, messageContent);
				return false;
			}
		}
		else {
			searchStartPosition = mentionEndPosition + 1;
		}
	}
	return true;
}

void ProcessCustomEmojis(char[] messageContent, int maxContentLength) {
	int searchStartPosition = 0, emojiPosition;

	while((emojiPosition = StrContains(messageContent[searchStartPosition], "<:", false)) != -1) {
		int actualEmojiPosition = searchStartPosition + emojiPosition;
		int emojiEndPosition = StrContains(messageContent[actualEmojiPosition], ">", false);
		if (emojiEndPosition == -1) {
			break;
		}
		emojiEndPosition += actualEmojiPosition;

		int nameColonPosition = -1;
		for(int i = actualEmojiPosition + 2; i < emojiEndPosition; i++) {
			if (messageContent[i] == ':') {
				nameColonPosition = i;
				break;
			}
		}

		if (nameColonPosition != -1) {
			char extractedEmojiName[64];
			int emojiNameLength = nameColonPosition - (actualEmojiPosition + 2);
			if (emojiNameLength > 0 && emojiNameLength < sizeof extractedEmojiName) {
				CopySubstring(messageContent, actualEmojiPosition + 2, emojiNameLength, extractedEmojiName, sizeof extractedEmojiName);

				char fullEmojiMarkup[128];
				CopySubstring(messageContent, actualEmojiPosition, emojiEndPosition - actualEmojiPosition + 1, fullEmojiMarkup, sizeof fullEmojiMarkup);

				char emojiReplacement[128];
				Format(emojiReplacement, sizeof emojiReplacement, ":%s:", extractedEmojiName);

				ReplaceString(messageContent, maxContentLength, fullEmojiMarkup, emojiReplacement, false);
				searchStartPosition = 0;
			}
			else {
				searchStartPosition = emojiEndPosition + 1;
			}
		}
		else {
			searchStartPosition = emojiEndPosition + 1;
		}
	}

	searchStartPosition = 0;
	while((emojiPosition = StrContains(messageContent[searchStartPosition], "<a:", false)) != -1) {
		int actualEmojiPosition = searchStartPosition + emojiPosition;
		int emojiEndPosition = StrContains(messageContent[actualEmojiPosition], ">", false);
		if (emojiEndPosition == -1) {
			break;
		}
		emojiEndPosition += actualEmojiPosition;

		int nameColonPosition = -1;
		for(int i = actualEmojiPosition + 3; i < emojiEndPosition; i++) {
			if (messageContent[i] == ':') {
				nameColonPosition = i;
				break;
			}
		}

		if (nameColonPosition != -1) {
			char extractedEmojiName[64];
			int emojiNameLength = nameColonPosition - (actualEmojiPosition + 3);
			if (emojiNameLength > 0 && emojiNameLength < sizeof extractedEmojiName) {
				CopySubstring(messageContent, actualEmojiPosition + 3, emojiNameLength, extractedEmojiName, sizeof extractedEmojiName);

				char fullEmojiMarkup[128];
				CopySubstring(messageContent, actualEmojiPosition, emojiEndPosition - actualEmojiPosition + 1, fullEmojiMarkup, sizeof fullEmojiMarkup);

				char emojiReplacement[128];
				Format(emojiReplacement, sizeof emojiReplacement, ":%s:", extractedEmojiName);

				ReplaceString(messageContent, maxContentLength, fullEmojiMarkup, emojiReplacement, false);
				searchStartPosition = 0;
			}
			else {
				searchStartPosition = emojiEndPosition + 1;
			}
		}
		else {
			searchStartPosition = emojiEndPosition + 1;
		}
	}
}

void LogDiscordAPIError(HTTPStatus status, const char[] context, const char[] additionalInfo = "") {
	char errorMsg[256];

	switch(status) {
		case HTTPStatus_Unauthorized:
		{
			Format(errorMsg, sizeof errorMsg, "Discord API: Unauthorized in %s - check bot token", context);
		}
		case HTTPStatus_Forbidden:
		{
			Format(errorMsg, sizeof errorMsg, "Discord API: Forbidden in %s - check bot permissions", context);
		}
		case HTTPStatus_NotFound:
		{
			Format(errorMsg, sizeof errorMsg, "Discord API: Not Found in %s - check IDs", context);
		}
		case HTTPStatus_TooManyRequests:
		{
			Format(errorMsg, sizeof errorMsg, "Discord API: Rate limited in %s - backing off", context);
		}
		default:
		{
			Format(errorMsg, sizeof errorMsg, "Discord API: Error %d in %s", view_as<int>(status), context);
		}
	}

	if (strlen(additionalInfo) > 0) {
		Format(errorMsg, sizeof errorMsg, "%s - %s", errorMsg, additionalInfo);
	}

	LogError(errorMsg);
}

void PrintDiscordMessage(const char[] username, const char[] message, const char[] userColor = "", bool showPrefix = true) {
	char finalUserColor[16];
	if (strlen(userColor) == 0) {
		Format(finalUserColor, sizeof finalUserColor, "\x07%s", g_sDiscordColor);
	}
	else {
		strcopy(finalUserColor, sizeof finalUserColor, userColor);
	}

	if (showPrefix && g_bShowDiscordPrefix) {
		PrintToChatAll("%s[Discord] %s%s%s :  %s", DISCORD_PREFIX_COLOR, finalUserColor, username, CHAT_COLOR_RESET, message);
	}
	else {
		PrintToChatAll("%s%s%s :  %s", finalUserColor, username, CHAT_COLOR_RESET, message);
	}
}

void ProcessDiscordMentions(const char[] userId, const char[] username, const char[] rawContent) {
	char processedContent[512];
	strcopy(processedContent, sizeof processedContent, rawContent);

	if (!ProcessUserMentions(processedContent, sizeof processedContent, userId, username)) {
		return ;
	}

	if (!ProcessChannelMentions(processedContent, sizeof processedContent, userId, username)) {
		return ;
	}

	if (!ProcessRoleMentions(processedContent, sizeof processedContent, userId, username)) {
		return ;
	}

	ProcessCustomEmojis(processedContent, sizeof processedContent);

	GetDiscordRoleColor(userId, username, processedContent);
}

void GetDiscordUserName(const char[] mentionUserId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hUserNameCache, mentionUserId, "User");
		ProcessDiscordMentions(originalUserId, username, content);
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, mentionUserId);

	DataPack pack = new DataPack();
	pack.WriteString(mentionUserId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordUserResponse, pack);
}

public void OnDiscordUserResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char mentionUserId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(mentionUserId, sizeof mentionUserId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char displayName[64] = "User";

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONObject member = view_as<JSONObject>(response.Data);
		JSONObject user = view_as<JSONObject>(member.Get("user"));

		if (user != null) {
			if (!user.GetString("display_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
				if (!user.GetString("global_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
					user.GetString("username", displayName, sizeof displayName);
				}
			}
			delete user;
		}
		delete member;
	}

	SetCachedDiscordData(g_hUserNameCache, mentionUserId, displayName);
	ProcessDiscordMentions(originalUserId, username, content);
}

void GetDiscordUserNickname(const char[] userId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hUserNickCache, userId, username);
		GetDiscordRoleColor(userId, username, content);
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, userId);

	DataPack pack = new DataPack();
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordUserNicknameResponse, pack);
}

public void OnDiscordUserNicknameResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char displayName[64];
	strcopy(displayName, sizeof displayName, username);

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONObject member = view_as<JSONObject>(response.Data);

		if (!member.GetString("nick", displayName, sizeof displayName) || strlen(displayName) == 0) {
			JSONObject user = view_as<JSONObject>(member.Get("user"));
			if (user != null) {
				if (!user.GetString("display_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
					if (!user.GetString("global_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
						user.GetString("username", displayName, sizeof displayName);
					}
				}
				delete user;
			}
		}
		delete member;
	}

	SetCachedDiscordData(g_hUserNickCache, userId, displayName);
	GetDiscordRoleColor(userId, displayName, content);
}

void GetDiscordChannelName(const char[] channelId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0) {
		SetCachedDiscordData(g_hChannelNameCache, channelId, "channel");
		ProcessDiscordMentions(originalUserId, username, content);
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/channels/%s", DISCORD_API_BASE_URL, channelId);

	DataPack pack = new DataPack();
	pack.WriteString(channelId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordChannelResponse, pack);
}

public void OnDiscordChannelResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char channelId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(channelId, sizeof channelId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char channelName[64] = "channel";

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONObject channel = view_as<JSONObject>(response.Data);
		channel.GetString("name", channelName, sizeof channelName);
		delete channel;
	}

	SetCachedDiscordData(g_hChannelNameCache, channelId, channelName);
	ProcessDiscordMentions(originalUserId, username, content);
}

void GetDiscordRoleName(const char[] roleId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hRoleNameCache, roleId, "Role");
		ProcessDiscordMentions(originalUserId, username, content);
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/roles", DISCORD_API_BASE_URL, g_sGuildId);

	DataPack pack = new DataPack();
	pack.WriteString(roleId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordRoleNameResponse, pack);
}

public void OnDiscordRoleNameResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char roleId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(roleId, sizeof roleId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char roleName[64] = "Role";

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONArray roles = view_as<JSONArray>(response.Data);
		if (roles != null) {
			for(int i = 0; i < roles.Length; i++) {
				JSONObject role = view_as<JSONObject>(roles.Get(i));
				if (role == null)
					continue;

				char currentRoleId[32];
				role.GetString("id", currentRoleId, sizeof currentRoleId);

				if (StrEqual(roleId, currentRoleId)) {
					role.GetString("name", roleName, sizeof roleName);
					delete role;
					break;
				}
				delete role;
			}
			delete roles;
		}
	}

	SetCachedDiscordData(g_hRoleNameCache, roleId, roleName);
	ProcessDiscordMentions(originalUserId, username, content);
}

void GetDiscordRoleColor(const char[] userId, const char[] username, const char[] content) {
	bool hasGuildConfig = (strlen(g_sGuildId) > 0 && strlen(g_sBotToken) > 0);
	bool needsNickname = g_bUseNicknames && hasGuildConfig;
	bool hasNickname = false;
	char cachedNick[64];

	if (needsNickname) {
		hasNickname = GetCachedDiscordData(g_hUserNickCache, userId, cachedNick, sizeof cachedNick, DISCORD_NICK_TTL);
	}

	char displayName[64];
	bool useNicknameForDisplay = (needsNickname && hasNickname && strlen(cachedNick) > 0);
	if (useNicknameForDisplay) {
		strcopy(displayName, sizeof displayName, cachedNick);
	}
	else {
		strcopy(displayName, sizeof displayName, username);
	}

	if (needsNickname && !hasNickname) {
		GetDiscordUserNickname(userId, username, content);
		return ;
	}

	bool canUseRoleColors = (g_bUseRoleColors && hasGuildConfig);
	if (!canUseRoleColors) {
		PrintDiscordMessage(displayName, content);
		return ;
	}

	char cachedColor[8];
	if (GetCachedDiscordData(g_hUserColorCache, userId, cachedColor, sizeof cachedColor, DISCORD_COLOR_TTL)) {
		if (strlen(cachedColor) > 0) {
			PrintDiscordMessage(displayName, content, cachedColor);
		}
		else {
			PrintDiscordMessage(displayName, content);
		}
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, userId);

	DataPack pack = new DataPack();
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordMemberResponse, pack);
}

public void OnDiscordMemberResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char colorPrefix[8] = "";
	char displayName[64];
	strcopy(displayName, sizeof displayName, username);

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONObject member = view_as<JSONObject>(response.Data);

		if (g_bUseNicknames) {
			if (!member.GetString("nick", displayName, sizeof displayName) || strlen(displayName) == 0) {
				JSONObject user = view_as<JSONObject>(member.Get("user"));
				if (user != null) {
					if (!user.GetString("display_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
						if (!user.GetString("global_name", displayName, sizeof displayName) || strlen(displayName) == 0) {
							user.GetString("username", displayName, sizeof displayName);
						}
					}
					delete user;
				}
			}

			SetCachedDiscordData(g_hUserNickCache, userId, displayName);
		}
		else {
			JSONObject user = view_as<JSONObject>(member.Get("user"));
			if (user != null) {
				user.GetString("username", displayName, sizeof displayName);
				delete user;
			}
		}

		JSONArray roles = view_as<JSONArray>(member.Get("roles"));

		if (roles != null && roles.Length > 0) {
			GetTopRoleColor(roles, userId, displayName, content);
			delete member;
			return ;
		}

		if (roles != null) {
			delete roles;
		}
		delete member;
	}

	SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);

	if (strlen(colorPrefix) > 0) {
		PrintDiscordMessage(displayName, content, colorPrefix);
	}
	else {
		PrintDiscordMessage(displayName, content);
	}
}

void GetTopRoleColor(JSONArray roleIds, const char[] userId, const char[] username, const char[] content) {
	if (roleIds == null || roleIds.Length == 0) {
		SetCachedDiscordData(g_hUserColorCache, userId, "");
		PrintDiscordMessage(username, content);
		return ;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/roles", DISCORD_API_BASE_URL, g_sGuildId);

	DataPack pack = new DataPack();
	pack.WriteCell(view_as<int>(roleIds));
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordRolesResponse, pack);
}

public void OnDiscordRolesResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	JSONArray userRoleIds = view_as<JSONArray>(pack.ReadCell());
	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char colorPrefix[16] = "";

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONArray allRoles = view_as<JSONArray>(response.Data);
		if (allRoles != null) {
			int highestPosition = -1;
			int topRoleColor = 0;

			for(int i = 0; i < userRoleIds.Length; i++) {
				char roleId[32];
				userRoleIds.GetString(i, roleId, sizeof roleId);

				for(int j = 0; j < allRoles.Length; j++) {
					JSONObject role = view_as<JSONObject>(allRoles.Get(j));
					if (role == null)
						continue;

					char currentRoleId[32];
					role.GetString("id", currentRoleId, sizeof currentRoleId);

					if (StrEqual(roleId, currentRoleId)) {
						int position = role.GetInt("position");
						int color = role.GetInt("color");

						if (position > highestPosition && color > 0) {
							highestPosition = position;
							topRoleColor = color;
						}
						delete role;
						break;
					}
					delete role;
				}
			}

			if (topRoleColor > 0) {
				Format(colorPrefix, sizeof colorPrefix, "\x07%06X", topRoleColor);
			}
			delete allRoles;
		}
	}

	delete userRoleIds;

	SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);

	if (strlen(colorPrefix) > 0) {
		PrintDiscordMessage(username, content, colorPrefix);
	}
	else {
		PrintDiscordMessage(username, content);
	}
}

void SendToDiscord(int client, const char[] message, bool isTeamChat = false) {
	if (strlen(g_sWebhookUrl) == 0) {
		return ;
	}

	char playerName[64], steamId[32], escapedPlayerName[128];
	GetClientName(client, playerName, sizeof playerName);

	if (g_iShowSteamId == 1) {
		GetClientAuthId(client, AuthId_Steam3, steamId, sizeof steamId);
	} else if (g_iShowSteamId == 2) {
		char tempSteamId[32];
		GetClientAuthId(client, AuthId_Steam2, tempSteamId, sizeof tempSteamId);
		Format(steamId, sizeof steamId, "(%s)", tempSteamId);
	}

	if (g_iShowSteamId > 0 && StrEqual(steamId, "STEAM_ID_STOP_IGNORING_RETVALS")) {
		strcopy(steamId, sizeof steamId, "[Steam Offline]");
	}

	EscapeUserContent(playerName, escapedPlayerName, sizeof escapedPlayerName);

	char webhookUsername[224];
	if (g_iShowSteamId > 0) {
		if (isTeamChat) {
			Format(webhookUsername, sizeof webhookUsername, "(TEAM) %s %s", playerName, steamId);
		}
		else {
			Format(webhookUsername, sizeof webhookUsername, "%s %s", playerName, steamId);
		}
	}
	else {
		if (isTeamChat) {
			Format(webhookUsername, sizeof webhookUsername, "(TEAM) %s", playerName);
		}
		else {
			Format(webhookUsername, sizeof webhookUsername, "%s", playerName);
		}
	}

	if (strlen(g_sSteamApiKey) > 0) {
		char steamId64[32];
		GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof steamId64);
		GetSteamAvatar(steamId64, webhookUsername, message);
	}
	else {
		SendWebhook(webhookUsername, message, "");
	}
}

void GetSteamAvatar(const char[] steamId64, const char[] webhookUsername, const char[] message) {
	char cachedPlayerAvatar[256];
	if (GetCachedAvatar(steamId64, cachedPlayerAvatar, sizeof cachedPlayerAvatar)) {
		SendWebhook(webhookUsername, message, cachedPlayerAvatar);
		return ;
	}

	char steamApiRequestUrl[256];
	Format(steamApiRequestUrl, sizeof steamApiRequestUrl, "%s/?key=%s&steamids=%s", STEAM_API_BASE_URL, g_sSteamApiKey, steamId64);

	DataPack steamRequestPack = new DataPack();
	steamRequestPack.WriteString(steamId64);
	steamRequestPack.WriteString(webhookUsername);
	steamRequestPack.WriteString(message);

	HTTPRequest steamApiRequest = CreateSteamAPIRequest(steamApiRequestUrl);
	steamApiRequest.Get(OnSteamResponse, steamRequestPack);
}

public void OnSteamResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char steamId64[32], webhookUsername[96], message[512], avatarUrl[256] = "";
	pack.ReadString(steamId64, sizeof steamId64);
	pack.ReadString(webhookUsername, sizeof webhookUsername);
	pack.ReadString(message, sizeof message);
	delete pack;

	if (response.Status == HTTPStatus_OK && response.Data != null) {
		JSONObject data = view_as<JSONObject>(response.Data);
		JSONObject responseObj = view_as<JSONObject>(data.Get("response"));
		JSONArray players = view_as<JSONArray>(responseObj.Get("players"));

		if (players != null && players.Length > 0) {
			JSONObject player = view_as<JSONObject>(players.Get(0));
			if (player != null) {
				player.GetString("avatarfull", avatarUrl, sizeof avatarUrl);
				delete player;
			}
		}

		if (players != null) {
			delete players;
		}
		if (responseObj != null) {
			delete responseObj;
		}
		delete data;
	}

	SetCachedAvatar(steamId64, avatarUrl);

	SendWebhook(webhookUsername, message, avatarUrl);
}

void SendWebhook(const char[] username, const char[] content, const char[] avatarUrl) {
	SendWebhookWithEscaping(username, content, avatarUrl, true);
}

void SendWebhookWithEscaping(const char[] username, const char[] content, const char[] avatarUrl, bool escapeContent) {
	if (strlen(g_sWebhookUrl) == 0) {
		LogError("Webhook URL is empty!");
		return ;
	}

	char finalContent[1024];
	if (escapeContent) {
		EscapeUserContent(content, finalContent, sizeof finalContent);
	}
	else {
		strcopy(finalContent, sizeof finalContent, content);
	}

	JSONObject payload = new JSONObject();
	payload.SetString("username", username);
	payload.SetString("content", finalContent);

	if (strlen(avatarUrl) > 0) {
		payload.SetString("avatar_url", avatarUrl);
	}

	HTTPRequest request = new HTTPRequest(g_sWebhookUrl);
	request.SetHeader("Content-Type", "application/json");
	char userAgent[64];
	Format(userAgent, sizeof userAgent, "SourceCord/%s", PLUGIN_VERSION);
	request.SetHeader("User-Agent", userAgent);
	request.Post(payload, OnWebhookResponse, INVALID_HANDLE);
}

public void OnWebhookResponse(HTTPResponse response, any data) {
	if (response.Status == HTTPStatus_NoContent || response.Status == HTTPStatus_OK) {
		return ;
	}

	if (view_as<int>(response.Status) == 0) {
		LogError("Webhook failed: Network/connection error");
		return ;
	}

	LogError("Webhook failed with HTTP status %d", response.Status);

	if (response.Data == null) {
		return ;
	}

	JSONObject errorData = view_as<JSONObject>(response.Data);
	if (errorData == null) {
		return ;
	}

	char errorMsg[256];
	if (errorData.GetString("message", errorMsg, sizeof errorMsg)) {
		LogError("Discord error: %s", errorMsg);
	}
}

void EscapeUserContent(const char[] input, char[] output, int maxlen) {
	int outputPos = 0;
	int inputLen = strlen(input);

	for(int i = 0; i < inputLen && outputPos < maxlen - 1; i++) {
		char c = input[i];

		bool isHttpUrl = (c == 'h' && i + 7 < inputLen && StrContains(input[i], "http://", false) == 0);
		bool isHttpsUrl = (c == 'h' && i + 8 < inputLen && StrContains(input[i], "https://", false) == 0);
		if (isHttpUrl || isHttpsUrl) {
			int urlEnd = i;
			while(urlEnd < inputLen && input[urlEnd] != ' ' && input[urlEnd] != '\n' && input[urlEnd] != '\r' && input[urlEnd] != '\t') {
				urlEnd++;
			}

			if (outputPos < maxlen - 1) {
				output[outputPos++] = '<';
			}

			for(int j = i; j < urlEnd && outputPos < maxlen - 1; j++) {
				output[outputPos++] = input[j];
			}

			if (outputPos < maxlen - 1) {
				output[outputPos++] = '>';
			}

			i = urlEnd - 1;
			continue;
		}

		switch(c) {
			case '*', '_', '`', '~', '|', '\\', '>', '#', '-':
			{
				if (outputPos < maxlen - 2) {
					output[outputPos++] = '\\';
					output[outputPos++] = c;
				}
			}
			default:
			{
				if (outputPos < maxlen - 1) {
					output[outputPos++] = c;
				}
			}
		}
	}

	output[outputPos] = '\0';
}

public void OnPluginEnd() {
	if (g_hUserColorCache != null) {
		delete g_hUserColorCache;
	}
	if (g_hUserNameCache != null) {
		delete g_hUserNameCache;
	}
	if (g_hUserNickCache != null) {
		delete g_hUserNickCache;
	}
	if (g_hUserAvatarCache != null) {
		delete g_hUserAvatarCache;
	}
	if (g_hChannelNameCache != null) {
		delete g_hChannelNameCache;
	}
	if (g_hRoleNameCache != null) {
		delete g_hRoleNameCache;
	}
	if (g_hMessageQueue != null) {
		delete g_hMessageQueue;
	}
	if (g_hProcessedMessages != null) {
		delete g_hProcessedMessages;
	}
	if (g_hMessageIdOrder != null) {
		delete g_hMessageIdOrder;
	}
}

void GetServerName(char[] buffer, int maxlen) {
	ConVar hostnameConVar = FindConVar("hostname");
	if (hostnameConVar != null) {
		hostnameConVar.GetString(buffer, maxlen);
		if (strlen(buffer) > 0) {
			return;
		}
	}

	strcopy(buffer, maxlen, "Server");
}

bool IsValidClient(int client) {
	return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}

bool IsValidHexColor(const char[] color) {
	int len = strlen(color);

	if (len != 6) {
		return false;
	}

	for(int i = 0; i < len; i++) {
		char c = color[i];
		if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
			return false;
		}
	}

	return true;
}

bool GetCachedAvatar(const char[] steamId64, char[] playerAvatarUrl, int maxAvatarUrlLength) {
	char cachedAvatarData[512];
	if (!g_hUserAvatarCache.GetString(steamId64, cachedAvatarData, sizeof cachedAvatarData)) {
		return false;
	}

	char avatarDataParts[2][256];
	if (ExplodeString(cachedAvatarData, "|", avatarDataParts, sizeof avatarDataParts, sizeof avatarDataParts[] ) != 2) {
		g_hUserAvatarCache.Remove(steamId64);
		return false;
	}

	float avatarCacheTime = StringToFloat(avatarDataParts[1]);
	float currentGameTime = GetGameTime();

	bool isAvatarCacheExpired = (currentGameTime - avatarCacheTime > AVATAR_CACHE_TTL);
	if (isAvatarCacheExpired) {
		g_hUserAvatarCache.Remove(steamId64);
		return false;
	}

	strcopy(playerAvatarUrl, maxAvatarUrlLength, avatarDataParts[0]);
	return strlen(playerAvatarUrl) > 0;
}

void SetCachedAvatar(const char[] steamId64, const char[] avatarUrl) {
	if (strlen(avatarUrl) == 0) {
		return ;
	}

	char cachedData[512];
	float currentTime = GetGameTime();
	Format(cachedData, sizeof cachedData, "%s|%.2f", avatarUrl, currentTime);
	g_hUserAvatarCache.SetString(steamId64, cachedData);
}

bool GetCachedDiscordData(StringMap cache, const char[] key, char[] data, int maxlen, float ttl) {
	char cachedData[512];
	if (!cache.GetString(key, cachedData, sizeof cachedData)) {
		return false;
	}

	char parts[2][256];
	if (ExplodeString(cachedData, "|", parts, sizeof parts, sizeof parts[] ) != 2) {
		cache.Remove(key);
		return false;
	}

	float cachedTime = StringToFloat(parts[1]);
	float currentTime = GetGameTime();

	bool isCacheExpired = (currentTime - cachedTime > ttl);
	if (isCacheExpired) {
		cache.Remove(key);
		return false;
	}

	strcopy(data, maxlen, parts[0]);
	return strlen(data) > 0;
}

void SetCachedDiscordData(StringMap cache, const char[] key, const char[] data) {
	if (strlen(data) == 0) {
		return ;
	}

	char cachedData[512];
	float currentTime = GetGameTime();
	Format(cachedData, sizeof cachedData, "%s|%.2f", data, currentTime);
	cache.SetString(key, cachedData);
}
