void InitializeConfig() {
	g_cvUpdateInterval = CreateConVar("sc_interval", "1.0", "Discord check interval (seconds)", FCVAR_NOTIFY, true, 1.0, true, 10.0);
	g_cvLogConnections = CreateConVar("sc_log_connections", "1", "Log player connect/disconnects (off, basic, with IP)", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvUseRoleColors = CreateConVar("sc_use_role_colors", "1", "Use Discord role colors for usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvUseNicknames = CreateConVar("sc_use_nicknames", "1", "Use Discord server nicknames instead of global usernames", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvShowSteamId = CreateConVar("sc_show_steam_id", "1", "Show Steam ID in Discord messages (off, steamID3, steamID)", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	g_cvShowDiscordPrefix = CreateConVar("sc_show_discord_prefix", "1", "Show [Discord] prefix in chat messages", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDiscordColor = CreateConVar("sc_discord_color", DISCORD_DEFAULT_COLOR, "Hex color code for Discord usernames (without # prefix)", FCVAR_NOTIFY);

	// hook convar changes
	g_cvUpdateInterval.AddChangeHook(OnConVarChanged);
	g_cvLogConnections.AddChangeHook(OnConVarChanged);
	g_cvUseRoleColors.AddChangeHook(OnConVarChanged);
	g_cvUseNicknames.AddChangeHook(OnConVarChanged);
	g_cvShowSteamId.AddChangeHook(OnConVarChanged);
	g_cvShowDiscordPrefix.AddChangeHook(OnConVarChanged);
	g_cvDiscordColor.AddChangeHook(OnConVarChanged);

	// auto-create and execute config file
	AutoExecConfig(true, "sourcecord");
}


public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	CacheSettings();

	if (convar == g_cvUpdateInterval) {
		StartTimer();
	}
}


void CacheSettings() {
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


void LoadCredentials() {
	char configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof configPath, "configs/sourcecord.cfg");

	KeyValues kv = new KeyValues("SourceCord");
	if (!kv.ImportFromFile(configPath)) {
		LogError("Failed to load credentials config: %s", configPath);
		LogMessage("Operational settings (cvars) are located in cfg\\sourcemod\\sourcecord.cfg");

		CreateExampleCredentials(configPath);

		delete kv;
		return;
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
		LogError("Bot token not configured! Please edit credentials config: %s", configPath);
	}
	if (strlen(g_sChannelId) == 0) {
		LogError("Channel ID not configured! Please edit credentials config: %s", configPath);
	}

	LogMessage("Credentials loaded successfully from %s", configPath);
	LogMessage("Operational settings (cvars) are located in cfg\\sourcemod\\sourcecord.cfg");
}


void CreateExampleCredentials(const char[] configPath) {
	File file = OpenFile(configPath, "w");
	if (file == null) {
		LogError("Failed to create example credentials config at %s", configPath);
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
	LogMessage("Created example credentials config at %s", configPath);
	LogMessage("Edit this file with your bot token, webhook URL, and Steam API key, then restart the plugin.");
	LogMessage("Operational settings (cvars) will auto-generate in cfg\\sourcemod\\sourcecord.cfg");
}
