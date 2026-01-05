forward void GetDiscordUserName(const char[] userId, const char[] originalUserId, const char[] username, const char[] content);

forward void GetDiscordChannelName(const char[] channelId, const char[] originalUserId, const char[] username, const char[] content);

forward void GetDiscordRoleName(const char[] roleId, const char[] originalUserId, const char[] username, const char[] content);

forward void GetDiscordRoleColor(const char[] userId, const char[] username, const char[] content);

bool ProcessUserMentions(char[] content, int maxlen, const char[] userId, const char[] username) {
	int searchStart = 0, pos;
	char mentionPattern[32], mentionId[32];

	while ((pos = StrContains(content[searchStart], "<@", false)) != -1) {
		int actualPos = searchStart + pos;

		if (actualPos + 2 < strlen(content) && content[actualPos + 2] == '&') {
			searchStart = actualPos + 1;
			continue;
		}

		int mentionEndPosition = StrContains(content[actualPos], ">", false);
		if (mentionEndPosition == -1) {
			break;
		}
		mentionEndPosition += actualPos;

		int userIdStartPosition = actualPos + 2;
		int userIdLength = mentionEndPosition - userIdStartPosition;
		if (userIdLength > 0 && userIdLength < 32) {
			CopySubstring(content, userIdStartPosition, userIdLength, mentionId, sizeof mentionId);

			char cachedDisplayName[64];
			if (GetCachedDiscordData(g_hUserNameCache, mentionId, cachedDisplayName, sizeof cachedDisplayName, DISCORD_LONG_TTL)) {
				Format(mentionPattern, sizeof mentionPattern, "<@%s>", mentionId);
				char mentionReplacement[128];
				Format(mentionReplacement, sizeof mentionReplacement, "@%s", cachedDisplayName);
				ReplaceString(content, maxlen, mentionPattern, mentionReplacement, false);
				searchStart = 0;
			}
			else {
				GetDiscordUserName(mentionId, userId, username, content);
				return false;
			}
		}
		else {
			searchStart = mentionEndPosition + 1;
		}
	}
	return true;
}


bool ProcessChannelMentions(char[] content, int maxlen, const char[] userId, const char[] username) {
	int searchStart = 0, pos;
	char mentionPattern[32], mentionId[32];

	while ((pos = StrContains(content[searchStart], "<#", false)) != -1) {
		int actualPos = searchStart + pos;
		int mentionEndPosition = StrContains(content[actualPos], ">", false);
		if (mentionEndPosition == -1) {
			break;
		}
		mentionEndPosition += actualPos;

		int idStartPosition = actualPos + 2;
		int idLength = mentionEndPosition - idStartPosition;
		if (idLength > 0 && idLength < 32) {
			CopySubstring(content, idStartPosition, idLength, mentionId, sizeof mentionId);

			char cachedName[64];
			if (GetCachedDiscordData(g_hChannelNameCache, mentionId, cachedName, sizeof cachedName, DISCORD_LONG_TTL)) {
				Format(mentionPattern, sizeof mentionPattern, "<#%s>", mentionId);
				char mentionReplacement[128];
				Format(mentionReplacement, sizeof mentionReplacement, "#%s", cachedName);
				ReplaceString(content, maxlen, mentionPattern, mentionReplacement, false);
				searchStart = 0;
			}
			else {
				GetDiscordChannelName(mentionId, userId, username, content);
				return false;
			}
		}
		else {
			searchStart = mentionEndPosition + 1;
		}
	}
	return true;
}


bool ProcessRoleMentions(char[] content, int maxlen, const char[] userId, const char[] username) {
	int searchStart = 0, pos;
	char mentionPattern[32], mentionId[32];

	while ((pos = StrContains(content[searchStart], "<@&", false)) != -1) {
		int actualPos = searchStart + pos;
		int mentionEndPosition = StrContains(content[actualPos], ">", false);
		if (mentionEndPosition == -1) {
			break;
		}
		mentionEndPosition += actualPos;

		int idStartPosition = actualPos + 3;
		int idLength = mentionEndPosition - idStartPosition;
		if (idLength > 0 && idLength < 32) {
			CopySubstring(content, idStartPosition, idLength, mentionId, sizeof mentionId);

			char cachedName[64];
			if (GetCachedDiscordData(g_hRoleNameCache, mentionId, cachedName, sizeof cachedName, DISCORD_LONG_TTL)) {
				Format(mentionPattern, sizeof mentionPattern, "<@&%s>", mentionId);
				char mentionReplacement[128];
				Format(mentionReplacement, sizeof mentionReplacement, "@%s", cachedName);
				ReplaceString(content, maxlen, mentionPattern, mentionReplacement, false);
				searchStart = 0;
			}
			else {
				GetDiscordRoleName(mentionId, userId, username, content);
				return false;
			}
		}
		else {
			searchStart = mentionEndPosition + 1;
		}
	}
	return true;
}


public void ProcessDiscordMentions(const char[] userId, const char[] username, const char[] rawContent) {
	char processedContent[512];
	strcopy(processedContent, sizeof processedContent, rawContent);

	if (!ProcessUserMentions(processedContent, sizeof processedContent, userId, username)) {
		return;
	}

	if (!ProcessChannelMentions(processedContent, sizeof processedContent, userId, username)) {
		return;
	}

	if (!ProcessRoleMentions(processedContent, sizeof processedContent, userId, username)) {
		return;
	}

	ProcessCustomEmojis(processedContent, sizeof processedContent);

	GetDiscordRoleColor(userId, username, processedContent);
}
