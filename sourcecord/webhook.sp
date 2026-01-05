void SendToDiscord(int client, const char[] message, bool isTeamChat = false) {
	if (strlen(g_sWebhookUrl) == 0) {
		return;
	}

	char playerName[64], steamId[32], webhookUsername[224];
	GetClientName(client, playerName, sizeof playerName);
	GetFormattedSteamId(client, steamId, sizeof steamId);
	FormatWebhookUsername(playerName, steamId, isTeamChat, webhookUsername, sizeof webhookUsername);

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
	if (GetCachedDiscordData(g_hUserAvatarCache, steamId64, cachedPlayerAvatar, sizeof cachedPlayerAvatar, AVATAR_CACHE_TTL)) {
		SendWebhook(webhookUsername, message, cachedPlayerAvatar);
		return;
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

		delete players;
		delete responseObj;
		delete data;
	}

	SetCachedDiscordData(g_hUserAvatarCache, steamId64, avatarUrl);

	SendWebhook(webhookUsername, message, avatarUrl);
}


void SendWebhook(const char[] username, const char[] content, const char[] avatarUrl, bool escapeContent = true) {
	if (strlen(g_sWebhookUrl) == 0) {
		LogError("Webhook URL is empty!");
		return;
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
	SetUserAgent(request);

	request.Post(payload, OnWebhookResponse, INVALID_HANDLE);
}


public void OnWebhookResponse(HTTPResponse response, any data) {
	if (response.Status == HTTPStatus_NoContent || response.Status == HTTPStatus_OK) {
		return;
	}

	if (view_as<int>(response.Status) == 0) {
		LogError("Webhook failed: Network/connection error");
		return;
	}

	LogError("Webhook failed with HTTP status %d", response.Status);

	if (response.Data == null) {
		return;
	}

	JSONObject errorData = view_as<JSONObject>(response.Data);
	if (errorData == null) {
		return;
	}

	char errorMsg[256];
	if (errorData.GetString("message", errorMsg, sizeof errorMsg)) {
		LogError("Discord error: %s", errorMsg);
	}
}
