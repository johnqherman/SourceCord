// connection state tracking
bool g_bClientConnected[MAXPLAYERS + 1];

// team chat tracking
bool g_bClientTeamChat[MAXPLAYERS + 1];


void FormatConnectionMessage(const char[] playerName, const char[] steamId, const char[] clientIP, const char[] reason, char[] output, int maxlen) {
	bool hasSteamId = (strlen(steamId) > 0);
	bool hasIP = (strlen(clientIP) > 0);
	bool isDisconnect = (strlen(reason) > 0);

	if (hasIP && hasSteamId) {
		if (isDisconnect) {
			Format(output, maxlen, "**%s** %s (%s) disconnected (%s)", playerName, steamId, clientIP, reason);
		}
		else {
			Format(output, maxlen, "**%s** %s (%s) connected to the server", playerName, steamId, clientIP);
		}
	}
	else if (hasIP) {
		if (isDisconnect) {
			Format(output, maxlen, "**%s** (%s) disconnected (%s)", playerName, clientIP, reason);
		}
		else {
			Format(output, maxlen, "**%s** (%s) connected to the server", playerName, clientIP);
		}
	}
	else if (hasSteamId) {
		if (isDisconnect) {
			Format(output, maxlen, "**%s** %s disconnected (%s)", playerName, steamId, reason);
		}
		else {
			Format(output, maxlen, "**%s** %s connected to the server", playerName, steamId);
		}
	}
	else {
		if (isDisconnect) {
			Format(output, maxlen, "**%s** disconnected (%s)", playerName, reason);
		}
		else {
			Format(output, maxlen, "**%s** connected to the server", playerName);
		}
	}
}


void InitializeChatIntegration() {
	for (int i = 1; i <= MaxClients; i++) {
		g_bClientConnected[i] = false;
		g_bClientTeamChat[i] = false;
	}

	HookEvent("player_say", Event_PlayerSay);
	HookEvent("player_activate", Event_PlayerConnect);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
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

	char playerName[64], escapedPlayerName[128], steamId[32], clientIP[32], msg[256];

	GetClientName(client, playerName, sizeof playerName);
	EscapeUserContent(playerName, escapedPlayerName, sizeof escapedPlayerName);
	GetFormattedSteamId(client, steamId, sizeof steamId);

	if (g_iLogConnections == 2) {
		GetClientIP(client, clientIP, sizeof clientIP);
	}
	else {
		clientIP[0] = '\0';
	}

	FormatConnectionMessage(escapedPlayerName, steamId, clientIP, "", msg, sizeof msg);

	char serverName[64];
	GetServerName(serverName, sizeof serverName);
	SendWebhook(serverName, msg, "", false);

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
	     clientIP[32],
	     reason[128],
	     msg[512];

	event.GetString("name", playerName, sizeof playerName);
	event.GetString("reason", reason, sizeof reason);
	EscapeUserContent(playerName, escapedPlayerName, sizeof escapedPlayerName);
	GetFormattedSteamId(client, steamId, sizeof steamId);

	if (g_iLogConnections == 2) {
		GetClientIP(client, clientIP, sizeof clientIP);
	}
	else {
		clientIP[0] = '\0';
	}

	FormatConnectionMessage(escapedPlayerName, steamId, clientIP, reason, msg, sizeof msg);

	char serverName[64];
	GetServerName(serverName, sizeof serverName);
	SendWebhook(serverName, msg, "", false);

	return Plugin_Continue;
}
