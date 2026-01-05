bool IsValidDiscordResponse(HTTPResponse response) {
	return (response.Status == HTTPStatus_OK && response.Data != null);
}


HTTPRequest CreateDiscordAPIRequest(const char[] url) {
	HTTPRequest request = new HTTPRequest(url);

	char authHeader[256];
	Format(authHeader, sizeof authHeader, "Bot %s", g_sBotToken);
	request.SetHeader("Authorization", authHeader);
	SetUserAgent(request);

	return request;
}


HTTPRequest CreateSteamAPIRequest(const char[] url) {
	HTTPRequest request = new HTTPRequest(url);
	SetUserAgent(request);

	return request;
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


void LogDiscordAPIError(HTTPStatus status, const char[] context, const char[] additionalInfo = "") {
	char errorMsg[256];

	switch (status) {
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
