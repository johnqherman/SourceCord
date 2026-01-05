#define DISCORD_API_BASE_URL "https://discord.com/api/v10"
#define STEAM_API_BASE_URL "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002"
#define DISCORD_DEFAULT_COLOR "5865F2"
#define DISCORD_PREFIX_COLOR "\x075865F2"
#define CHAT_COLOR_RESET "\x01"
#define MAX_RETRY_DELAY 60.0
#define AVATAR_CACHE_TTL 1800.0 // 30 minutes
#define DISCORD_NICK_TTL 1800.0 // 30 minutes
#define DISCORD_COLOR_TTL 3600.0 // 1 hour
#define DISCORD_LONG_TTL 86400.0 // 24 hours

// convars
ConVar g_cvUpdateInterval,
       g_cvLogConnections,
       g_cvUseRoleColors,
       g_cvUseNicknames,
       g_cvShowSteamId,
       g_cvShowDiscordPrefix,
       g_cvDiscordColor;

// settings
float g_fUpdateInterval;
int g_iLogConnections;
bool g_bUseRoleColors;
bool g_bUseNicknames;
int g_iShowSteamId;
bool g_bShowDiscordPrefix;
char g_sDiscordColor[8];

// credentials
char g_sBotToken[128],
     g_sChannelId[32],
     g_sGuildId[32],
     g_sWebhookUrl[256],
     g_sSteamApiKey[64];

// error handling
int g_iFailedRequests;
float g_fNextRetryTime;

// cache
StringMap g_hUserColorCache,
          g_hUserNameCache,
          g_hUserNickCache,
          g_hUserAvatarCache,
          g_hChannelNameCache,
          g_hRoleNameCache;

// message queuing
ArrayList g_hMessageQueue;
StringMap g_hProcessedMessages;
ArrayList g_hMessageIdOrder;
