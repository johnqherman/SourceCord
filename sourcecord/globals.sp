#define DISCORD_API_BASE_URL "https://discord.com/api/v10"
#define STEAM_API_BASE_URL "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002"
#define DISCORD_DEFAULT_COLOR "5865F2"
#define DISCORD_PREFIX_COLOR "\x075865F2"
#define CHAT_COLOR_RESET "\x01"
#define MAX_RETRY_DELAY 60.0
#define THIRTY_MINUTES 1800.0
#define ONE_HOUR 3600.0
#define ONE_DAY 86400.0

// convars
ConVar g_cvUpdateInterval,
       g_cvLogConnections,
       g_cvLogMapChanges,
       g_cvUseRoleColors,
       g_cvUseNicknames,
       g_cvShowSteamId,
       g_cvShowDiscordPrefix,
       g_cvDiscordColor,
       g_cvAllowUserPings,
       g_cvAllowRolePings;

// settings
float g_fUpdateInterval;
int g_iLogConnections;
bool g_bLogMapChanges;
bool g_bUseRoleColors;
bool g_bUseNicknames;
int g_iShowSteamId;
bool g_bShowDiscordPrefix;
char g_sDiscordColor[8];
bool g_bAllowUserPings;
bool g_bAllowRolePings;

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
          g_hRoleNameCache,
          g_hGuildEmojiCache,
          g_hGuildMemberCache,
          g_hGuildRoleCache,
          g_hEmojiMap;

// emoji state
bool g_bEmojiFetched;
float g_fEmojiLastFetch;

// member/role ping state
bool g_bMembersFetched;
float g_fMembersLastFetch;
bool g_bRolesFetched;
float g_fRolesLastFetch;

// message queuing
ArrayList g_hMessageQueue;
StringMap g_hProcessedMessages;
ArrayList g_hMessageIdOrder;
