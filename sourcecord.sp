#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ripext>

#define PLUGIN_VERSION "1.0.1"

#define AVATAR_CACHE_TTL 1800.0  // 30 minutes
#define DISCORD_NICK_TTL 1800.0  // 30 minutes
#define DISCORD_COLOR_TTL 3600.0  // 1 hour 
#define DISCORD_LONG_TTL 86400.0  // 24 hours

public Plugin myinfo = {
    name = "SourceCord",
    author = "sharkobarko", 
    description = "Discord chat integration for Source Engine games",
    version = PLUGIN_VERSION,
    url = "https://github.com/johnqherman/SourceCord/"
};

// convars                
ConVar g_cvConfigFile;                            
ConVar g_cvUpdateInterval;                        
ConVar g_cvLogConnections;                        
ConVar g_cvUseRoleColors;                         
ConVar g_cvUseNicknames;                          
                                                  
// settings           
float g_fUpdateInterval;                          
bool g_bLogConnections;                           
bool g_bUseRoleColors;                            
bool g_bUseNicknames;                             
                                                  
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

public void OnPluginStart() {
    g_cvConfigFile = CreateConVar("sc_config_file", "sourcecord", "Config filename (without .cfg)", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvUpdateInterval = CreateConVar("sc_interval", "1.0", "Discord check interval (seconds)", FCVAR_NOTIFY, true, 0.1, true, 10.0);
    g_cvLogConnections = CreateConVar("sc_log_connections", "0", "Log player connect/disconnects", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvUseRoleColors = CreateConVar("sc_use_role_colors", "0", "Use Discord role colors for usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvUseNicknames = CreateConVar("sc_use_nicknames", "1", "Use Discord server nicknames instead of global usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);

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
    
    // hook player events
    HookEvent("player_say", Event_PlayerSay);
    HookEvent("player_connect", Event_PlayerConnect);
    HookEvent("player_disconnect", Event_PlayerDisconnect);
    
    // hook convar changes
    g_cvConfigFile.AddChangeHook(OnConVarChanged);
    g_cvUpdateInterval.AddChangeHook(OnConVarChanged);
    g_cvLogConnections.AddChangeHook(OnConVarChanged);
    g_cvUseRoleColors.AddChangeHook(OnConVarChanged);
    g_cvUseNicknames.AddChangeHook(OnConVarChanged);
    
    // create operational config file if it doesn't exist
    char configFile[64];
    g_cvConfigFile.GetString(configFile, sizeof(configFile));
    AutoExecConfig(true, configFile);
    
}

public void OnConfigsExecuted() {
    char configFile[64];
    g_cvConfigFile.GetString(configFile, sizeof(configFile));
    if (strlen(configFile) > 0 && !StrEqual(configFile, "sourcecord")) {
        ServerCommand("exec sourcemod/%s.cfg", configFile);
    }
    
    LoadSensitiveCredentials();
    LoadOperationalSettings();
}

public void OnMapStart() {
    StartTimer();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (convar == g_cvConfigFile) {
        ServerCommand("exec sourcemod/%s.cfg", newValue);
        return;
    }
    
    LoadOperationalSettings();

    if (convar == g_cvUpdateInterval) {
        StartTimer();
    }
}

void LoadOperationalSettings() {
    g_fUpdateInterval = g_cvUpdateInterval.FloatValue;
    g_bLogConnections = g_cvLogConnections.BoolValue;
    g_bUseRoleColors = g_cvUseRoleColors.BoolValue;
    g_bUseNicknames = g_cvUseNicknames.BoolValue;
}

void LoadSensitiveCredentials() {
    char configFile[64];
    g_cvConfigFile.GetString(configFile, sizeof(configFile));
    
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/%s.cfg", configFile);
    
    KeyValues kv = new KeyValues("SourceCord");
    if (!kv.ImportFromFile(configPath)) {
        LogError("Failed to load configuration file: %s", configPath);
        
        CreateExampleConfig(configPath);
        
        LogError("Please edit the config file with your Discord credentials and restart the plugin.");
        delete kv;
        return;
    }
    
    // load discord settings
    if (kv.JumpToKey("Discord", false)) {
        kv.GetString("bot_token", g_sBotToken, sizeof(g_sBotToken), "");
        kv.GetString("channel_id", g_sChannelId, sizeof(g_sChannelId), "");
        kv.GetString("guild_id", g_sGuildId, sizeof(g_sGuildId), "");
        kv.GetString("webhook_url", g_sWebhookUrl, sizeof(g_sWebhookUrl), "");
        kv.GoBack();
    }
    
    // load steam api key
    if (kv.JumpToKey("Steam", false)) {
        kv.GetString("api_key", g_sSteamApiKey, sizeof(g_sSteamApiKey), "");
        kv.GoBack();
    }
    
    delete kv;
    
    // validate required settings
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
        return;
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
    LogMessage("Please edit this file with your credentials and restart the plugin.");
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

public Action Timer_CheckDiscord(Handle timer) {
    if (strlen(g_sBotToken) == 0 || strlen(g_sChannelId) == 0) {
        return Plugin_Continue;
    }
    
    // check if we're in retry backoff period
    if (g_fNextRetryTime > 0.0 && GetGameTime() < g_fNextRetryTime) {
        return Plugin_Continue;
    }
    
    char url[256];
    if (strlen(g_sLastMessageId) > 0) {
        Format(url, sizeof(url), "https://discord.com/api/v10/channels/%s/messages?limit=5&after=%s", g_sChannelId, g_sLastMessageId);
    } else {
        Format(url, sizeof(url), "https://discord.com/api/v10/channels/%s/messages?limit=5", g_sChannelId);
    }
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    request.SetHeader("Accept", "application/json");
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordResponse, INVALID_HANDLE);
    
    return Plugin_Continue;
}

public void OnDiscordResponse(HTTPResponse response, any data) {
    if (response.Status != HTTPStatus_OK) {
        HandleDiscordError(response.Status);
        return;
    }
    
    // reset failed requests counter on success
    g_iFailedRequests = 0;
    g_fNextRetryTime = 0.0;
    
    if (response.Data == null) {
        return;
    }
    
    JSONArray messages = view_as<JSONArray>(response.Data);
    if (messages == null || messages.Length == 0) {
        if (messages != null) {
            delete messages;
        }
        return;
    }
    
    // process messages in reverse order (oldest first)
    int messageCount = messages.Length;
    char latestMessageId[32];
    
    for (int i = messageCount - 1; i >= 0; i--) {
        JSONObject message = view_as<JSONObject>(messages.Get(i));
        if (message == null) {
            continue;
        }
        
        char messageId[32];
        message.GetString("id", messageId, sizeof(messageId));
        
        // skip if already processed
        bool alreadyProcessed;
        if (g_hProcessedMessages.GetValue(messageId, alreadyProcessed)) {
            delete message;
            continue;
        }
        
        // mark as processed and track insertion order
        g_hProcessedMessages.SetValue(messageId, true);
        g_hMessageIdOrder.PushString(messageId);
        strcopy(latestMessageId, sizeof(latestMessageId), messageId);
        
        // skip initial setup
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
        author.GetString("username", username, sizeof(username));
        author.GetString("id", userId, sizeof(userId));
        message.GetString("content", content, sizeof(content));
        
        delete author;
        delete message;
        
        if (strlen(content) > 0) {
            QueueMessageForProcessing(userId, username, content);
        }
    }
    
    // update last message ID to newest message
    if (strlen(latestMessageId) > 0) {
        strcopy(g_sLastMessageId, sizeof(g_sLastMessageId), latestMessageId);
    }
    
    delete messages;
    ProcessMessageQueue();
    
    static int cleanupCounter = 0;
    cleanupCounter++;

    // cleanup every 100 successful responses
    if (cleanupCounter >= 100) {
        CleanupProcessedMessages();
        cleanupCounter = 0;
    }
}

void CleanupProcessedMessages() {
    // keep only 100 most recent processed IDs
    int maxCacheSize = 100;
    if (g_hProcessedMessages.Size <= maxCacheSize) {
        return;
    }
    
    int currentSize = g_hProcessedMessages.Size;
    int entriesToRemove = currentSize - maxCacheSize;
    
    LogMessage("LRU cleanup: removing %d oldest entries (current size: %d -> target: %d)", 
        entriesToRemove, currentSize, maxCacheSize);
    
    // FIFO from order tracking array
    for (int i = 0; i < entriesToRemove && g_hMessageIdOrder.Length > 0; i++) {
        char oldestId[32];
        g_hMessageIdOrder.GetString(0, oldestId, sizeof(oldestId));
        g_hMessageIdOrder.Erase(0);
        g_hProcessedMessages.Remove(oldestId);
    }
    
    LogMessage("LRU cleanup completed (final size: %d)", g_hProcessedMessages.Size);
}

void HandleDiscordError(HTTPStatus status) {
    if (status == HTTPStatus_Unauthorized) {
        LogError("Discord API: Unauthorized - check your bot token");
    } else if (status == HTTPStatus_Forbidden) {
        LogError("Discord API: Forbidden - bot lacks permissions or channel access");
    } else if (status == HTTPStatus_NotFound) {
        LogError("Discord API: Not Found - check your channel ID");
    } else if (status == HTTPStatus_TooManyRequests) {
        LogError("Discord API: Rate limited - increasing retry delay");
    } else {
        LogError("Discord API request failed with status: %d", view_as<int>(status));
    }
    
    // exponential backoff
    g_iFailedRequests++;
    float backoffDelay = Pow(2.0, float(g_iFailedRequests - 1)) * g_fUpdateInterval;
    if (backoffDelay > 60.0) { // 60s max
        backoffDelay = 60.0;
    }
    
    g_fNextRetryTime = GetGameTime() + backoffDelay;
    LogMessage("Discord retry scheduled in %.1f seconds (attempt %d)", backoffDelay, g_iFailedRequests);
}

void QueueMessageForProcessing(const char[] userId, const char[] username, const char[] content) {
    char messageData[512];
    Format(messageData, sizeof(messageData), "%s|%s|%s", userId, username, content);
    g_hMessageQueue.PushString(messageData);
}

void ProcessMessageQueue() {
    int queueSize = g_hMessageQueue.Length;
    if (queueSize == 0) {
        return;
    }
    
    // process <= 5 messages per batch
    int processCount = (queueSize > 5) ? 5 : queueSize;
    
    for (int i = 0; i < processCount; i++) {
        char messageData[512];
        g_hMessageQueue.GetString(0, messageData, sizeof(messageData));
        g_hMessageQueue.Erase(0);
        
        // parse message data
        char parts[3][256];
        if (ExplodeString(messageData, "|", parts, sizeof(parts), sizeof(parts[])) == 3) {
            ProcessDiscordMentions(parts[0], parts[1], parts[2]);
        }
    }
    
    // if there are still messages queued, process in next cycle
    if (g_hMessageQueue.Length > 0) {
        LogMessage("Message queue has %d remaining messages, will process next batch in %.1f seconds", 
            g_hMessageQueue.Length, g_fUpdateInterval);
    }
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsValidClient(client) || IsChatTrigger()) {
        return Plugin_Continue;
    }
    
    char message[256];
    event.GetString("text", message, sizeof(message));
    
    if (strlen(message) == 0) {
        return Plugin_Continue;
    }
    
    bool isTeamChat = event.GetBool("teamonly");
    SendToDiscord(client, message, isTeamChat);
    return Plugin_Continue;
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bLogConnections) return Plugin_Continue;
    
    if (event.GetBool("bot")) {
        return Plugin_Continue;
    }
    
    char playerName[64], escapedPlayerName[128], msg[256];
    event.GetString("name", playerName, sizeof(playerName));
    EscapeUserContent(playerName, escapedPlayerName, sizeof(escapedPlayerName));
    Format(msg, sizeof(msg), "**%s** connected to the server", escapedPlayerName);
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    SendWebhookWithEscaping("Server", msg, "", false);
    
    return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bLogConnections) return Plugin_Continue;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (client > 0 && IsFakeClient(client)) {
        return Plugin_Continue;
    }
    
    char playerName[64], escapedPlayerName[128], reason[128], escapedReason[256], msg[512];
    event.GetString("name", playerName, sizeof(playerName));
    event.GetString("reason", reason, sizeof(reason));
    EscapeUserContent(playerName, escapedPlayerName, sizeof(escapedPlayerName));
    EscapeUserContent(reason, escapedReason, sizeof(escapedReason));
    Format(msg, sizeof(msg), "**%s** disconnected (%s)", escapedPlayerName, escapedReason);
    
    SendWebhookWithEscaping("Server", msg, "", false);
    
    return Plugin_Continue;
}

void CopySubstring(const char[] source, int startPos, int length, char[] dest, int maxlen) {
    int copyLen = length;
    if (copyLen >= maxlen) {
        copyLen = maxlen - 1;
    }
    
    for (int i = 0; i < copyLen; i++) {
        dest[i] = source[startPos + i];
    }
    dest[copyLen] = '\0';
}

void ProcessDiscordMentions(const char[] userId, const char[] username, const char[] rawContent) {
    char processedContent[512];
    strcopy(processedContent, sizeof(processedContent), rawContent);
    
    // process user mentions
    char mentionPattern[32], mentionId[32];
    int searchStart = 0;
    int pos;

    while ((pos = StrContains(processedContent[searchStart], "<@", false)) != -1) {
        int actualPos = searchStart + pos;
        
        // skip role mentions
        if (actualPos + 2 < strlen(processedContent) && processedContent[actualPos + 2] == '&') {
            searchStart = actualPos + 1;
            continue;
        }
        
        int endPos = StrContains(processedContent[actualPos], ">", false);
        
        if (endPos == -1) {
            break;
        }

        endPos += actualPos;
        
        int idStart = actualPos + 2;
        int idLen = endPos - idStart;

        if (idLen > 0 && idLen < sizeof(mentionId)) {
            CopySubstring(processedContent, idStart, idLen, mentionId, sizeof(mentionId));
            
            char cachedName[64];
            if (GetCachedDiscordData(g_hUserNameCache, mentionId, cachedName, sizeof(cachedName), DISCORD_LONG_TTL)) {
                Format(mentionPattern, sizeof(mentionPattern), "<@%s>", mentionId);
                char replacement[96];
                Format(replacement, sizeof(replacement), "@%s", cachedName);
                ReplaceString(processedContent, sizeof(processedContent), mentionPattern, replacement, false);
                searchStart = 0;
            } else {
                GetDiscordUserName(mentionId, userId, username, processedContent);
                return;
            }
        } else {
            searchStart = endPos + 1;
        }
    }
    
    // process channel mentions
    searchStart = 0;
    while ((pos = StrContains(processedContent[searchStart], "<#", false)) != -1) {
        int actualPos = searchStart + pos;
        int endPos = StrContains(processedContent[actualPos], ">", false);
        if (endPos == -1) break;
        endPos += actualPos;
        
        int idStart = actualPos + 2;
        int idLen = endPos - idStart;
        if (idLen > 0 && idLen < sizeof(mentionId)) {
            CopySubstring(processedContent, idStart, idLen, mentionId, sizeof(mentionId));
            
            char cachedName[64];
            if (GetCachedDiscordData(g_hChannelNameCache, mentionId, cachedName, sizeof(cachedName), DISCORD_LONG_TTL)) {
                Format(mentionPattern, sizeof(mentionPattern), "<#%s>", mentionId);
                char replacement[96];
                Format(replacement, sizeof(replacement), "#%s", cachedName);
                ReplaceString(processedContent, sizeof(processedContent), mentionPattern, replacement, false);
                searchStart = 0;
            } else {
                GetDiscordChannelName(mentionId, userId, username, processedContent);
                return;
            }
        } else {
            searchStart = endPos + 1;
        }
    }
    
    // process role mentions
    searchStart = 0;
    while ((pos = StrContains(processedContent[searchStart], "<@&", false)) != -1) {
        int actualPos = searchStart + pos;
        int endPos = StrContains(processedContent[actualPos], ">", false);
        if (endPos == -1) break;
        endPos += actualPos;
        
        int idStart = actualPos + 3;
        int idLen = endPos - idStart;
        if (idLen > 0 && idLen < sizeof(mentionId)) {
            CopySubstring(processedContent, idStart, idLen, mentionId, sizeof(mentionId));
            
            char cachedRoleName[64];
            if (GetCachedDiscordData(g_hRoleNameCache, mentionId, cachedRoleName, sizeof(cachedRoleName), DISCORD_LONG_TTL)) {
                Format(mentionPattern, sizeof(mentionPattern), "<@&%s>", mentionId);
                char replacement[96];
                Format(replacement, sizeof(replacement), "@%s", cachedRoleName);
                ReplaceString(processedContent, sizeof(processedContent), mentionPattern, replacement, false);
                searchStart = 0;
            } else {
                GetDiscordRoleName(mentionId, userId, username, processedContent);
                return;
            }
        } else {
            searchStart = endPos + 1;
        }
    }
    
    // process custom emojis
    searchStart = 0;
    while ((pos = StrContains(processedContent[searchStart], "<:", false)) != -1) {
        int actualPos = searchStart + pos;
        int endPos = StrContains(processedContent[actualPos], ">", false);
        if (endPos == -1) break;
        endPos += actualPos;
        
        int colonPos = -1;
        for (int i = actualPos + 2; i < endPos; i++) {
            if (processedContent[i] == ':') {
                colonPos = i;
                break;
            }
        }
        
        if (colonPos != -1) {
            char emojiName[64];
            int nameLen = colonPos - (actualPos + 2);
            if (nameLen > 0 && nameLen < sizeof(emojiName)) {
                CopySubstring(processedContent, actualPos + 2, nameLen, emojiName, sizeof(emojiName));
                
                char fullEmoji[128];
                CopySubstring(processedContent, actualPos, endPos - actualPos + 1, fullEmoji, sizeof(fullEmoji));
                
                char replacement[96];
                Format(replacement, sizeof(replacement), ":%s:", emojiName);
                
                ReplaceString(processedContent, sizeof(processedContent), fullEmoji, replacement, false);
                searchStart = 0;
            } else {
                searchStart = endPos + 1;
            }
        } else {
            searchStart = endPos + 1;
        }
    }
    
    // handle animated emojis
    searchStart = 0;
    while ((pos = StrContains(processedContent[searchStart], "<a:", false)) != -1) {
        int actualPos = searchStart + pos;
        int endPos = StrContains(processedContent[actualPos], ">", false);
        if (endPos == -1) break;
        endPos += actualPos;
        
        int colonPos = -1;
        for (int i = actualPos + 3; i < endPos; i++) {
            if (processedContent[i] == ':') {
                colonPos = i;
                break;
            }
        }
        
        if (colonPos != -1) {
            char emojiName[64];
            int nameLen = colonPos - (actualPos + 3);
            if (nameLen > 0 && nameLen < sizeof(emojiName)) {
                CopySubstring(processedContent, actualPos + 3, nameLen, emojiName, sizeof(emojiName));
                
                char fullEmoji[128];
                CopySubstring(processedContent, actualPos, endPos - actualPos + 1, fullEmoji, sizeof(fullEmoji));
                
                char replacement[96];
                Format(replacement, sizeof(replacement), ":%s:", emojiName);
                
                ReplaceString(processedContent, sizeof(processedContent), fullEmoji, replacement, false);
                searchStart = 0;
            } else {
                searchStart = endPos + 1;
            }
        } else {
            searchStart = endPos + 1;
        }
    }
    
    GetDiscordRoleColor(userId, username, processedContent);
}

void GetDiscordUserName(const char[] mentionUserId, const char[] originalUserId, const char[] username, const char[] content) {
    if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
        SetCachedDiscordData(g_hUserNameCache, mentionUserId, "User");
        ProcessDiscordMentions(originalUserId, username, content);
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/guilds/%s/members/%s", g_sGuildId, mentionUserId);
    
    DataPack pack = new DataPack();
    pack.WriteString(mentionUserId);
    pack.WriteString(originalUserId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordUserResponse, pack);
}

public void OnDiscordUserResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char mentionUserId[32], originalUserId[32], username[64], content[512];
    pack.ReadString(mentionUserId, sizeof(mentionUserId));
    pack.ReadString(originalUserId, sizeof(originalUserId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char displayName[64] = "User";
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONObject member = view_as<JSONObject>(response.Data);
        JSONObject user = view_as<JSONObject>(member.Get("user"));
        
        if (user != null) {
            // try display name, fallback to username
            if (!user.GetString("display_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                if (!user.GetString("global_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                    user.GetString("username", displayName, sizeof(displayName));
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
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/guilds/%s/members/%s", g_sGuildId, userId);
    
    DataPack pack = new DataPack();
    pack.WriteString(userId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordUserNicknameResponse, pack);
}

public void OnDiscordUserNicknameResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char userId[32], username[64], content[512];
    pack.ReadString(userId, sizeof(userId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char displayName[64];
    strcopy(displayName, sizeof(displayName), username);
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONObject member = view_as<JSONObject>(response.Data);
        
        // handle nicknames
        if (!member.GetString("nick", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
            JSONObject user = view_as<JSONObject>(member.Get("user"));
            if (user != null) {
                if (!user.GetString("display_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                    if (!user.GetString("global_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                        user.GetString("username", displayName, sizeof(displayName));
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
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/channels/%s", channelId);
    
    DataPack pack = new DataPack();
    pack.WriteString(channelId);
    pack.WriteString(originalUserId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordChannelResponse, pack);
}

public void OnDiscordChannelResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char channelId[32], originalUserId[32], username[64], content[512];
    pack.ReadString(channelId, sizeof(channelId));
    pack.ReadString(originalUserId, sizeof(originalUserId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char channelName[64] = "channel";
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONObject channel = view_as<JSONObject>(response.Data);
        channel.GetString("name", channelName, sizeof(channelName));
        delete channel;
    }
    
    SetCachedDiscordData(g_hChannelNameCache, channelId, channelName);
    ProcessDiscordMentions(originalUserId, username, content);
}

void GetDiscordRoleName(const char[] roleId, const char[] originalUserId, const char[] username, const char[] content) {
    if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
        SetCachedDiscordData(g_hRoleNameCache, roleId, "Role");
        ProcessDiscordMentions(originalUserId, username, content);
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/guilds/%s/roles", g_sGuildId);
    
    DataPack pack = new DataPack();
    pack.WriteString(roleId);
    pack.WriteString(originalUserId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordRoleNameResponse, pack);
}

public void OnDiscordRoleNameResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char roleId[32], originalUserId[32], username[64], content[512];
    pack.ReadString(roleId, sizeof(roleId));
    pack.ReadString(originalUserId, sizeof(originalUserId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char roleName[64] = "Role";
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONArray roles = view_as<JSONArray>(response.Data);
        if (roles != null) {
            // find role with matching ID
            for (int i = 0; i < roles.Length; i++) {
                JSONObject role = view_as<JSONObject>(roles.Get(i));
                if (role == null) continue;
                
                char currentRoleId[32];
                role.GetString("id", currentRoleId, sizeof(currentRoleId));
                
                if (StrEqual(roleId, currentRoleId)) {
                    role.GetString("name", roleName, sizeof(roleName));
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
    bool needsNickname = g_bUseNicknames && strlen(g_sGuildId) > 0 && strlen(g_sBotToken) > 0;
    bool hasNickname = false;
    char cachedNick[64];
    
    if (needsNickname) {
        hasNickname = GetCachedDiscordData(g_hUserNickCache, userId, cachedNick, sizeof(cachedNick), DISCORD_NICK_TTL);
    }
    
    // get display name
    char displayName[64];
    if (needsNickname && hasNickname && strlen(cachedNick) > 0) {
        strcopy(displayName, sizeof(displayName), cachedNick);
    } else {
        strcopy(displayName, sizeof(displayName), username);
    }
    
    // if nicknames are enabled but not cached, and we have required config, fetch
    if (needsNickname && !hasNickname) {
        GetDiscordUserNickname(userId, username, content);
        return;
    }
    
    if (!g_bUseRoleColors || strlen(g_sGuildId) == 0 || strlen(g_sBotToken) == 0) {
        PrintToChatAll("\x075865F2[Discord] %s\x01 :  %s", displayName, content);
        return;
    }
    
    char cachedColor[8];
    if (GetCachedDiscordData(g_hUserColorCache, userId, cachedColor, sizeof(cachedColor), DISCORD_COLOR_TTL)) {
        if (strlen(cachedColor) > 0) {
            PrintToChatAll("\x075865F2[Discord] %s%s\x01 :  %s", cachedColor, displayName, content);
        } else {
            PrintToChatAll("\x075865F2[Discord] %s\x01 :  %s", displayName, content);
        }
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/guilds/%s/members/%s", g_sGuildId, userId);
    
    DataPack pack = new DataPack();
    pack.WriteString(userId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordMemberResponse, pack);
}

public void OnDiscordMemberResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char userId[32], username[64], content[512];
    pack.ReadString(userId, sizeof(userId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char colorPrefix[8] = "";
    char displayName[64];
    strcopy(displayName, sizeof(displayName), username);
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONObject member = view_as<JSONObject>(response.Data);
        
        // handle nicknames
        if (g_bUseNicknames) {
            if (!member.GetString("nick", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                JSONObject user = view_as<JSONObject>(member.Get("user"));
                if (user != null) {
                    if (!user.GetString("display_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                        if (!user.GetString("global_name", displayName, sizeof(displayName)) || strlen(displayName) == 0) {
                            user.GetString("username", displayName, sizeof(displayName));
                        }
                    }
                    delete user;
                }
            }

            SetCachedDiscordData(g_hUserNickCache, userId, displayName);
        } else {
            JSONObject user = view_as<JSONObject>(member.Get("user"));
            if (user != null) {
                user.GetString("username", displayName, sizeof(displayName));
                delete user;
            }
        }
        
        JSONArray roles = view_as<JSONArray>(member.Get("roles"));
        
        if (roles != null && roles.Length > 0) {
            GetTopRoleColor(roles, userId, displayName, content);
            delete member;
            return;
        }
        
        if (roles != null) {
            delete roles;
        }
        delete member;
    }
    
    SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);
    
    if (strlen(colorPrefix) > 0) {
        PrintToChatAll("\x075865F2[Discord] %s%s\x01 :  %s", colorPrefix, displayName, content);
    } else {
        PrintToChatAll("\x075865F2[Discord] %s\x01 :  %s", displayName, content);
    }
}

void GetTopRoleColor(JSONArray roleIds, const char[] userId, const char[] username, const char[] content) {
    if (roleIds == null || roleIds.Length == 0) {
        SetCachedDiscordData(g_hUserColorCache, userId, "");
        PrintToChatAll("\x075865F2[Discord] %s\x01 :  %s", username, content);
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://discord.com/api/v10/guilds/%s/roles", g_sGuildId);
    
    DataPack pack = new DataPack();
    pack.WriteCell(view_as<int>(roleIds));
    pack.WriteString(userId);
    pack.WriteString(username);
    pack.WriteString(content);
    
    HTTPRequest request = new HTTPRequest(url);
    
    char authHeader[256];
    Format(authHeader, sizeof(authHeader), "Bot %s", g_sBotToken);
    
    request.SetHeader("Authorization", authHeader);
    char userAgent[64];
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    
    request.Get(OnDiscordRolesResponse, pack);
}

public void OnDiscordRolesResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    JSONArray userRoleIds = view_as<JSONArray>(pack.ReadCell());
    char userId[32], username[64], content[512];
    pack.ReadString(userId, sizeof(userId));
    pack.ReadString(username, sizeof(username));
    pack.ReadString(content, sizeof(content));
    delete pack;
    
    char colorPrefix[16] = "";
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONArray allRoles = view_as<JSONArray>(response.Data);
        if (allRoles != null) {
            int highestPosition = -1;
            int topRoleColor = 0;
            
            for (int i = 0; i < userRoleIds.Length; i++) {
                char roleId[32];
                userRoleIds.GetString(i, roleId, sizeof(roleId));
                
                for (int j = 0; j < allRoles.Length; j++) {
                    JSONObject role = view_as<JSONObject>(allRoles.Get(j));
                    if (role == null) continue;
                    
                    char currentRoleId[32];
                    role.GetString("id", currentRoleId, sizeof(currentRoleId));
                    
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
            
            // add role color prefix
            if (topRoleColor > 0) {
                Format(colorPrefix, sizeof(colorPrefix), "\x07%06X", topRoleColor);
            }
            delete allRoles;
        }
    }
    
    delete userRoleIds;

    SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);
    
    if (strlen(colorPrefix) > 0) {
        PrintToChatAll("\x075865F2[Discord] %s%s\x01 :  %s", colorPrefix, username, content);
    } else {
        PrintToChatAll("\x075865F2[Discord] %s\x01 :  %s", username, content);
    }
}

void SendToDiscord(int client, const char[] message, bool isTeamChat = false) {
    if (strlen(g_sWebhookUrl) == 0) {
        return;
    }
    
    char playerName[64], steamId[32], escapedPlayerName[128];
    GetClientName(client, playerName, sizeof(playerName));
    GetClientAuthId(client, AuthId_Steam3, steamId, sizeof(steamId));
    
    if (StrEqual(steamId, "STEAM_ID_STOP_IGNORING_RETVALS")) {
        strcopy(steamId, sizeof(steamId), "[Steam Offline]");
    }
    
    EscapeUserContent(playerName, escapedPlayerName, sizeof(escapedPlayerName));
    
    char webhookUsername[224];
    if (isTeamChat) {
        Format(webhookUsername, sizeof(webhookUsername), "(TEAM) %s %s", escapedPlayerName, steamId);
    } else {
        Format(webhookUsername, sizeof(webhookUsername), "%s %s", escapedPlayerName, steamId);
    }
    
    if (strlen(g_sSteamApiKey) > 0) {
        char steamId64[32];
        GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64));
        GetSteamAvatar(steamId64, webhookUsername, message);
    } else {
        SendWebhook(webhookUsername, message, "");
    }
}

void GetSteamAvatar(const char[] steamId64, const char[] webhookUsername, const char[] message) {
    // check avatar cache first
    char cachedAvatar[256];
    if (GetCachedAvatar(steamId64, cachedAvatar, sizeof(cachedAvatar))) {
        SendWebhook(webhookUsername, message, cachedAvatar);
        return;
    }
    
    char url[256];
    Format(url, sizeof(url), "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s", g_sSteamApiKey, steamId64);
    
    DataPack pack = new DataPack();
    pack.WriteString(steamId64);
    pack.WriteString(webhookUsername);
    pack.WriteString(message);
    
    HTTPRequest request = new HTTPRequest(url);
    request.Get(OnSteamResponse, pack);
}



public void OnSteamResponse(HTTPResponse response, DataPack pack) {
    pack.Reset();
    
    char steamId64[32], webhookUsername[96], message[512], avatarUrl[256] = "";
    pack.ReadString(steamId64, sizeof(steamId64));
    pack.ReadString(webhookUsername, sizeof(webhookUsername));
    pack.ReadString(message, sizeof(message));
    delete pack;
    
    if (response.Status == HTTPStatus_OK && response.Data != null) {
        JSONObject data = view_as<JSONObject>(response.Data);
        JSONObject responseObj = view_as<JSONObject>(data.Get("response"));
        JSONArray players = view_as<JSONArray>(responseObj.Get("players"));
        
        if (players != null && players.Length > 0) {
            JSONObject player = view_as<JSONObject>(players.Get(0));
            if (player != null) {
                player.GetString("avatarfull", avatarUrl, sizeof(avatarUrl));
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
        return;
    }
    
    char finalContent[1024];
    if (escapeContent) {
        EscapeUserContent(content, finalContent, sizeof(finalContent));
    } else {
        strcopy(finalContent, sizeof(finalContent), content);
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
    Format(userAgent, sizeof(userAgent), "SourceCord/%s", PLUGIN_VERSION);
    request.SetHeader("User-Agent", userAgent);
    request.Post(payload, OnWebhookResponse, INVALID_HANDLE);
}

public void OnWebhookResponse(HTTPResponse response, any data) {
    if (response.Status == HTTPStatus_NoContent || response.Status == HTTPStatus_OK) {
        return; // success
    }
    
    if (view_as<int>(response.Status) == 0) {
        LogError("Webhook failed: Network/connection error");
    } else {
        LogError("Webhook failed with HTTP status %d", response.Status);
        
        if (response.Data != null) {
            JSONObject errorData = view_as<JSONObject>(response.Data);
            if (errorData != null) {
                char errorMsg[256];
                if (errorData.GetString("message", errorMsg, sizeof(errorMsg))) {
                    LogError("Discord error: %s", errorMsg);
                }
            }
        }
    }
}

void EscapeUserContent(const char[] input, char[] output, int maxlen) {
    int outputPos = 0;
    int inputLen = strlen(input);
    
    for (int i = 0; i < inputLen && outputPos < maxlen - 1; i++) {
        char c = input[i];
        
        // wrap urls to prevent embeds
        if ((c == 'h' && i + 7 < inputLen && StrContains(input[i], "http://", false) == 0) ||
            (c == 'h' && i + 8 < inputLen && StrContains(input[i], "https://", false) == 0)) {            
            int urlEnd = i;
            while (urlEnd < inputLen && input[urlEnd] != ' ' && input[urlEnd] != '\n' && input[urlEnd] != '\r' && input[urlEnd] != '\t') {
                urlEnd++;
            }
            
            if (outputPos < maxlen - 1) {
                output[outputPos++] = '<';
            }
            
            for (int j = i; j < urlEnd && outputPos < maxlen - 1; j++) {
                output[outputPos++] = input[j];
            }
            
            if (outputPos < maxlen - 1) {
                output[outputPos++] = '>';
            }
            
            i = urlEnd - 1;
            continue;
        }
        
        // escape markdown characters
        switch (c) {
            case '*', '_', '`', '~', '|', '\\', '>', '#', '-': {
                if (outputPos < maxlen - 2) {
                    output[outputPos++] = '\\';
                    output[outputPos++] = c;
                }
            }
            default: {
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

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}

bool GetCachedAvatar(const char[] steamId64, char[] avatarUrl, int maxlen) {
    char cachedData[512];
    if (!g_hUserAvatarCache.GetString(steamId64, cachedData, sizeof(cachedData))) {
        return false;
    }
    
    // parse cached data: "avatarUrl|timestamp"
    char parts[2][256];
    if (ExplodeString(cachedData, "|", parts, sizeof(parts), sizeof(parts[])) != 2) {
        g_hUserAvatarCache.Remove(steamId64);
        return false;
    }
    
    float cachedTime = StringToFloat(parts[1]);
    float currentTime = GetGameTime();
    
    // check if expired
    if (currentTime - cachedTime > AVATAR_CACHE_TTL) {
        g_hUserAvatarCache.Remove(steamId64);
        return false;
    }
    
    strcopy(avatarUrl, maxlen, parts[0]);
    return strlen(avatarUrl) > 0;
}

void SetCachedAvatar(const char[] steamId64, const char[] avatarUrl) {
    if (strlen(avatarUrl) == 0) return;
    
    char cachedData[512];
    float currentTime = GetGameTime();
    Format(cachedData, sizeof(cachedData), "%s|%.2f", avatarUrl, currentTime);
    g_hUserAvatarCache.SetString(steamId64, cachedData);
}

bool GetCachedDiscordData(StringMap cache, const char[] key, char[] data, int maxlen, float ttl) {
    char cachedData[512];
    if (!cache.GetString(key, cachedData, sizeof(cachedData))) {
        return false;
    }
    
    // parse cached data: "data|timestamp"
    char parts[2][256];
    if (ExplodeString(cachedData, "|", parts, sizeof(parts), sizeof(parts[])) != 2) {
        cache.Remove(key);
        return false;
    }
    
    float cachedTime = StringToFloat(parts[1]);
    float currentTime = GetGameTime();
    
    // check if expired
    if (currentTime - cachedTime > ttl) {
        cache.Remove(key);
        return false;
    }
    
    strcopy(data, maxlen, parts[0]);
    return strlen(data) > 0;
}

void SetCachedDiscordData(StringMap cache, const char[] key, const char[] data) {
    if (strlen(data) == 0) return;
    
    char cachedData[512];
    float currentTime = GetGameTime();
    Format(cachedData, sizeof(cachedData), "%s|%.2f", data, currentTime);
    cache.SetString(key, cachedData);
}