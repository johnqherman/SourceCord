forward void ProcessDiscordMentions(const char[] userId, const char[] username, const char[] content);

void PrintDiscordMessage(const char[] username, const char[] message, const char[] userColor = "", bool showPrefix = true) {
	char finalUserColor[16];
	if (strlen(userColor) == 0) {
		Format(finalUserColor, sizeof finalUserColor, "\x07%s", g_sDiscordColor);
	}
	else {
		strcopy(finalUserColor, sizeof finalUserColor, userColor);
	}

	if (showPrefix && g_bShowDiscordPrefix) {
		PrintToChatAll("%s[Discord] %s%s%s :  %s", DISCORD_PREFIX_COLOR, finalUserColor, username, CHAT_COLOR_RESET, message);
	}
	else {
		PrintToChatAll("%s%s%s :  %s", finalUserColor, username, CHAT_COLOR_RESET, message);
	}
}


void ResolveDisplayName(JSONObject user, char[] displayName, int maxlen) {
	if (!user.GetString("display_name", displayName, maxlen) || strlen(displayName) == 0) {
		if (!user.GetString("global_name", displayName, maxlen) || strlen(displayName) == 0) {
			user.GetString("username", displayName, maxlen);
		}
	}
}


public void GetDiscordUserName(const char[] mentionUserId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hUserNameCache, mentionUserId, "User");
		ProcessDiscordMentions(originalUserId, username, content);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, mentionUserId);

	DataPack pack = new DataPack();
	pack.WriteString(mentionUserId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordUserResponse, pack);
}


public void OnDiscordUserResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char mentionUserId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(mentionUserId, sizeof mentionUserId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char displayName[64] = "User";

	if (IsValidDiscordResponse(response)) {
		JSONObject member = view_as<JSONObject>(response.Data);
		JSONObject user = view_as<JSONObject>(member.Get("user"));

		if (user != null) {
			ResolveDisplayName(user, displayName, sizeof displayName);
			delete user;
		}
		delete member;
	}

	SetCachedDiscordData(g_hUserNameCache, mentionUserId, displayName);
	ProcessDiscordMentions(originalUserId, username, content);
}


void GetDiscordUserNickname(const char[] userId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hUserNickCache, userId, username);
		GetDiscordRoleColor(userId, username, content);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, userId);

	DataPack pack = new DataPack();
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordUserNicknameResponse, pack);
}


public void OnDiscordUserNicknameResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char displayName[64];
	strcopy(displayName, sizeof displayName, username);

	if (IsValidDiscordResponse(response)) {
		JSONObject member = view_as<JSONObject>(response.Data);

		if (!member.GetString("nick", displayName, sizeof displayName) || strlen(displayName) == 0) {
			JSONObject user = view_as<JSONObject>(member.Get("user"));
			if (user != null) {
				ResolveDisplayName(user, displayName, sizeof displayName);
				delete user;
			}
		}
		delete member;
	}

	SetCachedDiscordData(g_hUserNickCache, userId, displayName);
	GetDiscordRoleColor(userId, displayName, content);
}


public void GetDiscordChannelName(const char[] channelId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0) {
		SetCachedDiscordData(g_hChannelNameCache, channelId, "channel");
		ProcessDiscordMentions(originalUserId, username, content);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/channels/%s", DISCORD_API_BASE_URL, channelId);

	DataPack pack = new DataPack();
	pack.WriteString(channelId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordChannelResponse, pack);
}


public void OnDiscordChannelResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char channelId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(channelId, sizeof channelId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char channelName[64] = "channel";

	if (IsValidDiscordResponse(response)) {
		JSONObject channel = view_as<JSONObject>(response.Data);
		channel.GetString("name", channelName, sizeof channelName);
		delete channel;
	}

	SetCachedDiscordData(g_hChannelNameCache, channelId, channelName);
	ProcessDiscordMentions(originalUserId, username, content);
}


public void GetDiscordRoleName(const char[] roleId, const char[] originalUserId, const char[] username, const char[] content) {
	if (strlen(g_sBotToken) == 0 || strlen(g_sGuildId) == 0) {
		SetCachedDiscordData(g_hRoleNameCache, roleId, "Role");
		ProcessDiscordMentions(originalUserId, username, content);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/roles", DISCORD_API_BASE_URL, g_sGuildId);

	DataPack pack = new DataPack();
	pack.WriteString(roleId);
	pack.WriteString(originalUserId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordRoleNameResponse, pack);
}


public void OnDiscordRoleNameResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char roleId[32], originalUserId[32], username[64], content[512];
	pack.ReadString(roleId, sizeof roleId);
	pack.ReadString(originalUserId, sizeof originalUserId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char roleName[64] = "Role";

	if (IsValidDiscordResponse(response)) {
		JSONArray roles = view_as<JSONArray>(response.Data);
		if (roles != null) {
			for (int i = 0; i < roles.Length; i++) {
				JSONObject role = view_as<JSONObject>(roles.Get(i));
				if (role == null)
					continue;

				char currentRoleId[32];
				role.GetString("id", currentRoleId, sizeof currentRoleId);

				if (StrEqual(roleId, currentRoleId)) {
					role.GetString("name", roleName, sizeof roleName);
					delete role;
					break;
				}
				delete role;
			}
			delete roles;
		}
	}

	SetCachedDiscordData(g_hRoleNameCache, roleId, roleName);
	ProcessDiscordMentions(originalUserId, username, content);
}


public void GetDiscordRoleColor(const char[] userId, const char[] username, const char[] content) {
	if (strlen(g_sGuildId) == 0 || strlen(g_sBotToken) == 0) {
		PrintDiscordMessage(username, content);
		return;
	}

	char displayName[64];
	strcopy(displayName, sizeof displayName, username);

	if (g_bUseNicknames) {
		char cachedNick[64];
		if (GetCachedDiscordData(g_hUserNickCache, userId, cachedNick, sizeof cachedNick, DISCORD_NICK_TTL)) {
			strcopy(displayName, sizeof displayName, cachedNick);
		}
		else {
			GetDiscordUserNickname(userId, username, content);
			return;
		}
	}

	if (!g_bUseRoleColors) {
		PrintDiscordMessage(displayName, content);
		return;
	}

	char cachedColor[8];
	if (GetCachedDiscordData(g_hUserColorCache, userId, cachedColor, sizeof cachedColor, DISCORD_COLOR_TTL)) {
		PrintDiscordMessage(displayName, content, cachedColor);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/members/%s", DISCORD_API_BASE_URL, g_sGuildId, userId);

	DataPack pack = new DataPack();
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);
	request.Get(OnDiscordMemberResponse, pack);
}


public void OnDiscordMemberResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char colorPrefix[8] = "", displayName[64];
	strcopy(displayName, sizeof displayName, username);

	if (IsValidDiscordResponse(response)) {
		JSONObject member = view_as<JSONObject>(response.Data);

		if (g_bUseNicknames) {
			if (!member.GetString("nick", displayName, sizeof displayName) || strlen(displayName) == 0) {
				JSONObject user = view_as<JSONObject>(member.Get("user"));
				if (user != null) {
					ResolveDisplayName(user, displayName, sizeof displayName);
					delete user;
				}
			}

			SetCachedDiscordData(g_hUserNickCache, userId, displayName);
		}
		else {
			JSONObject user = view_as<JSONObject>(member.Get("user"));
			if (user != null) {
				user.GetString("username", displayName, sizeof displayName);
				delete user;
			}
		}

		JSONArray roles = view_as<JSONArray>(member.Get("roles"));

		if (roles != null && roles.Length > 0) {
			GetTopRoleColor(roles, userId, displayName, content);
			delete member;
			return;
		}

		delete roles;
		delete member;
	}

	SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);
	PrintDiscordMessage(displayName, content, colorPrefix);
}


void GetTopRoleColor(JSONArray roleIds, const char[] userId, const char[] username, const char[] content) {
	if (roleIds == null || roleIds.Length == 0) {
		SetCachedDiscordData(g_hUserColorCache, userId, "");
		PrintDiscordMessage(username, content);
		return;
	}

	char url[256];
	Format(url, sizeof url, "%s/guilds/%s/roles", DISCORD_API_BASE_URL, g_sGuildId);

	DataPack pack = new DataPack();
	pack.WriteCell(view_as<int>(roleIds));
	pack.WriteString(userId);
	pack.WriteString(username);
	pack.WriteString(content);

	HTTPRequest request = CreateDiscordAPIRequest(url);

	request.Get(OnDiscordRolesResponse, pack);
}


public void OnDiscordRolesResponse(HTTPResponse response, DataPack pack) {
	pack.Reset();

	JSONArray userRoleIds = view_as<JSONArray>(pack.ReadCell());
	char userId[32], username[64], content[512];
	pack.ReadString(userId, sizeof userId);
	pack.ReadString(username, sizeof username);
	pack.ReadString(content, sizeof content);
	delete pack;

	char colorPrefix[16] = "";

	if (IsValidDiscordResponse(response)) {
		JSONArray allRoles = view_as<JSONArray>(response.Data);
		if (allRoles != null) {
			StringMap roleMap = new StringMap();
			for (int i = 0; i < allRoles.Length; i++) {
				JSONObject role = view_as<JSONObject>(allRoles.Get(i));
				if (role != null) {
					char roleId[32];
					role.GetString("id", roleId, sizeof roleId);
					roleMap.SetValue(roleId, i);
					delete role;
				}
			}

			int highestPosition = -1;
			int topRoleColor = 0;

			for (int i = 0; i < userRoleIds.Length; i++) {
				char roleId[32];
				userRoleIds.GetString(i, roleId, sizeof roleId);

				int roleIndex;
				if (roleMap.GetValue(roleId, roleIndex)) {
					JSONObject role = view_as<JSONObject>(allRoles.Get(roleIndex));
					if (role != null) {
						int position = role.GetInt("position");
						int color = role.GetInt("color");

						if (position > highestPosition && color > 0) {
							highestPosition = position;
							topRoleColor = color;
						}
						delete role;
					}
				}
			}

			delete roleMap;

			if (topRoleColor > 0) {
				Format(colorPrefix, sizeof colorPrefix, "\x07%06X", topRoleColor);
			}
			delete allRoles;
		}
	}

	delete userRoleIds;

	SetCachedDiscordData(g_hUserColorCache, userId, colorPrefix);
	PrintDiscordMessage(username, content, colorPrefix);
}
