#define CLEANUP_THRESHOLD 100
#define MAX_BATCH_SIZE 5
char g_sLastMessageId[32];
Handle g_hDiscordTimer;



void StartTimer() {
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
		return;
	}

	g_iFailedRequests = 0;
	g_fNextRetryTime = 0.0;

	if (response.Data == null) {
		return;
	}

	JSONArray messages = view_as<JSONArray>(response.Data);
	if (messages == null || messages.Length == 0) {
		delete messages;
		return;
	}

	int messageCount = messages.Length;
	char latestMessageId[32];

	for (int i = messageCount - 1; i >= 0; i--) {
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


void QueueMessageForProcessing(const char[] userId, const char[] username, const char[] content) {
	char messageData[512];
	Format(messageData, sizeof messageData, "%s|%s|%s", userId, username, content);
	g_hMessageQueue.PushString(messageData);
}


void ProcessMessageQueue() {
	int queueSize = g_hMessageQueue.Length;
	if (queueSize == 0) {
		return;
	}

	int processCount = (queueSize > MAX_BATCH_SIZE) ? MAX_BATCH_SIZE : queueSize;

	for (int i = 0; i < processCount; i++) {
		char messageData[512];
		g_hMessageQueue.GetString(0, messageData, sizeof messageData);
		g_hMessageQueue.Erase(0);

		char parts[3][256];
		if (ExplodeString(messageData, "|", parts, sizeof parts, sizeof parts[] ) == 3) {
			ProcessDiscordMentions(parts[0], parts[1], parts[2]);
		}
	}
}
