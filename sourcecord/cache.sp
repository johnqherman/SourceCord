void InitializeCaches() {
	g_hUserColorCache = new StringMap();
	g_hUserNameCache = new StringMap();
	g_hUserNickCache = new StringMap();
	g_hUserAvatarCache = new StringMap();
	g_hChannelNameCache = new StringMap();
	g_hRoleNameCache = new StringMap();
	g_hMessageQueue = new ArrayList(ByteCountToCells(512));
	g_hProcessedMessages = new StringMap();
	g_hMessageIdOrder = new ArrayList(ByteCountToCells(32));
	g_iFailedRequests = 0;
	g_fNextRetryTime = 0.0;
}


void CleanupProcessedMessages() {
	if (g_hProcessedMessages.Size <= 512) {
		return;
	}

	int currentSize = g_hProcessedMessages.Size;
	int entriesToRemove = currentSize - 512;

	for (int i = 0; i < entriesToRemove && g_hMessageIdOrder.Length > 0; i++) {
		char oldestId[32];
		g_hMessageIdOrder.GetString(0, oldestId, sizeof oldestId);
		g_hMessageIdOrder.Erase(0);
		g_hProcessedMessages.Remove(oldestId);
	}
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
		return;
	}

	char cachedData[512];
	float currentTime = GetGameTime();
	Format(cachedData, sizeof cachedData, "%s|%.2f", data, currentTime);
	cache.SetString(key, cachedData);
}


void CleanupCaches() {
	delete g_hUserColorCache;
	delete g_hUserNameCache;
	delete g_hUserNickCache;
	delete g_hUserAvatarCache;
	delete g_hChannelNameCache;
	delete g_hRoleNameCache;
	delete g_hMessageQueue;
	delete g_hProcessedMessages;
	delete g_hMessageIdOrder;
}
