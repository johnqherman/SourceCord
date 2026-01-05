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


void EscapeUserContent(const char[] input, char[] output, int maxlen) {
	int outputPos = 0;
	int inputLen = strlen(input);

	for (int i = 0; i < inputLen && outputPos < maxlen - 1; i++) {
		char c = input[i];

		bool isHttpUrl = (c == 'h' && i + 7 < inputLen && StrContains(input[i], "http://", false) == 0);
		bool isHttpsUrl = (c == 'h' && i + 8 < inputLen && StrContains(input[i], "https://", false) == 0);
		if (isHttpUrl || isHttpsUrl) {
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

		switch(c) {
			case '@':
			{
				bool isEveryoneOrHere = false;

				if (i + 8 <= inputLen) {
					if (StrContains(input[i], "@everyone", false) == 0) {
						isEveryoneOrHere = true;
					}
				}

				if (!isEveryoneOrHere && i + 4 <= inputLen) {
					if (StrContains(input[i], "@here", false) == 0) {
						isEveryoneOrHere = true;
					}
				}

				if (isEveryoneOrHere) {
					if (outputPos < maxlen - 4) {
						output[outputPos++] = c;
						output[outputPos++] = '\xE2';
						output[outputPos++] = '\x80';
						output[outputPos++] = '\x8B';
					}
				}
				else {
					if (outputPos < maxlen - 1) {
						output[outputPos++] = c;
					}
				}
			}
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


void ProcessCustomEmojis(char[] messageContent, int maxContentLength) {
	int pos = 0;
	int messageLen = strlen(messageContent);

	while (pos < messageLen) {
		if (messageContent[pos] != '<') {
			pos++;
			continue;
		}

		int nameStartOffset = 0;
		int prefixLen = 0;

		if (pos + 2 < messageLen && messageContent[pos + 1] == ':') {
			nameStartOffset = 2;
			prefixLen = 2;
		}
		else if (pos + 3 < messageLen && messageContent[pos + 1] == 'a' && messageContent[pos + 2] == ':') {
			nameStartOffset = 3;
			prefixLen = 3;
		}
		else {
			pos++;
			continue;
		}

		int emojiEndPos = -1;
		for (int i = pos + prefixLen; i < messageLen; i++) {
			if (messageContent[i] == '>') {
				emojiEndPos = i;
				break;
			}
		}

		if (emojiEndPos == -1) {
			pos++;
			continue;
		}

		int nameColonPos = -1;
		for (int i = pos + nameStartOffset; i < emojiEndPos; i++) {
			if (messageContent[i] == ':') {
				nameColonPos = i;
				break;
			}
		}

		if (nameColonPos == -1) {
			pos = emojiEndPos + 1;
			continue;
		}

		int emojiNameLength = nameColonPos - (pos + nameStartOffset);
		if (emojiNameLength <= 0 || emojiNameLength >= 64) {
			pos = emojiEndPos + 1;
			continue;
		}

		char extractedEmojiName[64];
		CopySubstring(messageContent, pos + nameStartOffset, emojiNameLength, extractedEmojiName, sizeof extractedEmojiName);

		char fullEmojiMarkup[128];
		int fullMarkupLen = emojiEndPos - pos + 1;
		CopySubstring(messageContent, pos, fullMarkupLen, fullEmojiMarkup, sizeof fullEmojiMarkup);

		char emojiReplacement[128];
		Format(emojiReplacement, sizeof emojiReplacement, ":%s:", extractedEmojiName);

		ReplaceString(messageContent, maxContentLength, fullEmojiMarkup, emojiReplacement, false);

		messageLen = strlen(messageContent);
		pos += strlen(emojiReplacement);
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


void GetFormattedSteamId(int client, char[] steamId, int maxlen) {
	if (g_iShowSteamId == 0) {
		steamId[0] = '\0';
		return;
	}

	if (g_iShowSteamId == 1) {
		GetClientAuthId(client, AuthId_Steam3, steamId, maxlen);
	}
	else if (g_iShowSteamId == 2) {
		char tempSteamId[32];
		GetClientAuthId(client, AuthId_Steam2, tempSteamId, sizeof tempSteamId);
		Format(steamId, maxlen, "(%s)", tempSteamId);
	}

	if (g_iShowSteamId > 0 && StrEqual(steamId, "STEAM_ID_STOP_IGNORING_RETVALS")) {
		strcopy(steamId, maxlen, "[Steam Offline]");
	}
}


void FormatWebhookUsername(const char[] playerName, const char[] steamId, bool isTeamChat, char[] output, int maxlen) {
	bool hasSteamId = (strlen(steamId) > 0);

	if (isTeamChat && hasSteamId) {
		Format(output, maxlen, "(TEAM) %s %s", playerName, steamId);
	}
	else if (isTeamChat) {
		Format(output, maxlen, "(TEAM) %s", playerName);
	}
	else if (hasSteamId) {
		Format(output, maxlen, "%s %s", playerName, steamId);
	}
	else {
		strcopy(output, maxlen, playerName);
	}
}


bool IsValidClient(int client) {
	return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}


void SetUserAgent(HTTPRequest request) {
	char userAgent[64];
	Format(userAgent, sizeof userAgent, "SourceCord/%s", PLUGIN_VERSION);
	request.SetHeader("User-Agent", userAgent);
}


bool IsValidHexColor(const char[] color) {
	int len = strlen(color);

	if (len != 6) {
		return false;
	}

	for (int i = 0; i < len; i++) {
		char c = color[i];
		if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
			return false;
		}
	}

	return true;
}
