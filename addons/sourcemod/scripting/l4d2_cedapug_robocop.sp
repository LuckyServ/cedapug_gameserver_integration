#include <sourcemod>
#include <json>
#include <l4d2_cedapug>
#include <left4dhooks>
#include <colors>

/* DISCONNECT POLICY */

// STEAMID:DISCONNECT_SECONDS
StringMap activePlayers;
float TIME_DISCONNECT_CHECK = 10.0;

// Threhold at which a players disconnect 
// check will get reset to 0
int THRESHOLD_IGNORE = 60;

// Threhold at which if more than N players 
// are past remove all active players
int THRESHOLD_GAME_ENDED = 180;

// Threhold for banning a player
int THRESHOLD_BAN = 240; // 240

// Threshold to warn a player about to be banned
int THRESHOLD_WARN = 30;

// AFK duration in seconds
int AFK_DURATION = 10;

/* STARTBAN POLICY */
Handle currentNewGameTimer = INVALID_HANDLE;
bool isRoundLive = false;
bool isReadyUp = false;
bool isPaused = false;

/* ENDPOINTS */
char PLAYERS_POST_KEY[] = "players=";
char BAN_ENDPOINT[] = "ban2";
char START_BAN_ENDPOINT[] = "startban";
char allPlayers[64][STEAMID_SIZE];

/* CONSTANTS */
char REASON_GAME_LEFT[MAX_STR_LEN] = "GAME_LEFT";
char REASON_GAME_AFK[MAX_STR_LEN] = "GAME_AFK";
char REASON_GAME_READYUP[MAX_STR_LEN] = "GAME_READYUP";

/* AFK */
float g_fButtonTime[MAXPLAYERS+1];
bool isPlayerReady[MAXPLAYERS+1];

/* FORWARDS */
GlobalForward cedapugBanForward;

public Plugin myinfo =
{
    name = "L4d2 CEDAPug Robocop",
    author = "Luckylock",
    description = "Provides automatic moderation for cedapug.",
    version = "14",
    url = "https://cedapug.com/"
};

public void OnPluginStart() {
    cedapugBanForward = new GlobalForward("OnCedapugBan", ET_Event, Param_Cell);
    RegAdminCmd("sm_startban", OnStartBan, ADMFLAG_GENERIC); 
    activePlayers = CreateTrie();
    currentNewGameTimer = CreateTimer(480.0, NewGameCreatedTookTooLong);
    AddCommandListener(Say_Callback, "say");
    AddCommandListener(Say_Callback, "say_team");
    HookEvent("round_start", RoundStart_Event, EventHookMode_Pre);
    SetAllPlayersUnready();
}

/* ANTI-VOTEKICKING */

Action CallvoteKickCheck(int client, const char[] command, int argc)
{
    if (!IS_CEDAPUG_GAME || argc < 2)
    {
        return Plugin_Continue;
    }

    char buffer[100];

    GetCmdArg(1, buffer, 100); // kick

    if (StrEqual(buffer, "kick"))
    {
        GetCmdArg(2, buffer, 100); // userid
        int userId = StringToInt(buffer);
        int targetClient = GetClientOfUserId(userId);

        if (IsHuman(targetClient))
        {
            char authId[MAX_STR_LEN];
            float value;

            GetClientAuthId(targetClient, AuthId_SteamID64, authId, STEAMID_SIZE, false);

            if (activePlayers.GetValue(authId, value))
            {
                CPrintToChat(client, "{green}CEDAPug: {default}Kicking an active player is not allowed.");
                return Plugin_Stop;
            }
        }
    }

    return Plugin_Continue;
}

/* DISCONNECT POLICY */

public void OnPause()
{
    isPaused = true;
}

public void OnUnpause()
{
    isPaused = false;
}

Action DisconnectCheck(Handle timer, Handle hndl)
{
    if (!IS_CEDAPUG_GAME)
    {
        return Plugin_Continue;
    }
    
    StringMapSnapshot snapshot = activePlayers.Snapshot();
    char steamId[STEAMID_SIZE];
    ArrayList playersToBan = new ArrayList(64, 0);
    int gameEndedCount = 0;

    for (int i = 0; i < activePlayers.Size; i++)
    {
        snapshot.GetKey(i, steamId, STEAMID_SIZE);
        float disconnectCount;
        activePlayers.GetValue(steamId, disconnectCount);

        if (IsSteamIdPlaying(steamId))
        {
            int count = RoundToNearest(disconnectCount);
            count -= count % THRESHOLD_IGNORE;
            activePlayers.SetValue(steamId, float(count), true);
        }
        else
        {
            disconnectCount += TIME_DISCONNECT_CHECK;
            activePlayers.SetValue(steamId, disconnectCount, true);

            if (disconnectCount >= THRESHOLD_GAME_ENDED)
            {
                gameEndedCount++;
            }

            if (THRESHOLD_BAN - disconnectCount <= THRESHOLD_WARN) {
                WarnPlayerDisconnect(steamId);
            }

            if (disconnectCount >= THRESHOLD_BAN) {
                activePlayers.Remove(steamId);
                playersToBan.PushString(steamId);
            }
        }
    }

    if (gameEndedCount >= 4)
    {
        CPrintToChatAll("{green}CEDAPug: {default}Robocop was about to ban too many people. It is now inactive for the rest of the round.")
        activePlayers.Clear();
    }
    else
    {
        for (int i = 0; i < playersToBan.Length; i++)
        {
            playersToBan.GetString(i, steamId, STEAMID_SIZE);

            if (GetClientIdFromSteamId(steamId) == 0)
            {
                BanPlayer(steamId, REASON_GAME_LEFT, "You left the game without finding a sub");
            }
            else if (isReadyUp)
            {
                BanPlayer(steamId, REASON_GAME_READYUP, "You failed to ready up in time");
            }
            else 
            {
                BanPlayer(steamId, REASON_GAME_AFK, "You have been kicked for being inactive");
            }
        }
    }

    delete playersToBan; 
    delete snapshot;

    return Plugin_Continue;
}

void WarnPlayerDisconnect(const char[] steamId) {
    int clientId = GetClientIdFromSteamId(steamId);
    
    if (clientId != 0) {
        if (isReadyUp)
        {
            CPrintToChat(clientId, "{green}CEDAPug: {default}You are about to banned for not readying up in time.")
        }
        else
        {
            CPrintToChat(clientId, "{green}CEDAPug: {default}You are about to be banned for being inactive or in spectator.")
        }
    }
}

int GetClientIdFromSteamId(const char[] steamId)
{
    if (strlen(steamId) == 0)
    {
        return 0;
    }

    char authId[MAX_STR_LEN];

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHuman(client))
        {
            GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);

            if (StrEqual(steamId, authId))
            {
                return client;
            }
        }
    }

    return 0;
}

bool IsSteamIdPlaying(const char[] steamId)
{
    int clientId = GetClientIdFromSteamId(steamId);
    return clientId != 0 && IsHumanPlaying(clientId) && !IsPlayerAfk(clientId);
}

void GetActivePlayers()
{
    char authId[MAX_STR_LEN];

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHumanPlaying(client)) {
            GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);
            activePlayers.SetValue(authId, 0.0, true);
        }
    }
}

/* STARTBAN POLICY */

Action OnStartBan(int client, int args)
{
    NewGameCreatedTookTooLong(INVALID_HANDLE);
}

Action NewGameCreatedTookTooLong(Handle timer)
{
    if (isRoundLive)
    {
        return Plugin_Stop;
    }

    char playersData[MAX_DATA_SIZE];
    JSON_Array allPlayersJSON = GetAllPlayers();
    allPlayersJSON.Encode(playersData, sizeof(playersData));
    json_cleanup_and_delete(allPlayersJSON);

    char dataToSend[MAX_DATA_SIZE];

    strcopy(dataToSend, sizeof(dataToSend), PLAYERS_POST_KEY);
    StrCat(dataToSend, sizeof(dataToSend), playersData);
    Cedapug_SendPostRequest(START_BAN_ENDPOINT, dataToSend, PrintResponseCallback);
    delete allPlayersJSON;

    currentNewGameTimer = INVALID_HANDLE;

    return Plugin_Stop;
}

JSON_Array GetAllPlayers() {
    JSON_Array allPlayersJSON = new JSON_Array();
    int playerCount = 0;

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHuman(client)) {
            GetClientAuthId(client, AuthId_SteamID64, allPlayers[playerCount], STEAMID_SIZE, false);
            allPlayersJSON.PushString(allPlayers[playerCount]);
            playerCount++;
        }
    }

    return allPlayersJSON;
}

/* GENERAL */

void BanPlayer(const char[] steamId, const char[] reason, const char[] kickReason)
{
    int clientId = GetClientIdFromSteamId(steamId);

    if (clientId != 0)
    {
        KickClient(clientId, kickReason);
    }

    char dataToSend[MAX_DATA_SIZE];
    strcopy(dataToSend, sizeof(dataToSend), "steamId=");
    StrCat(dataToSend, sizeof(dataToSend), steamId);
    StrCat(dataToSend, sizeof(dataToSend), "&reason=");
    StrCat(dataToSend, sizeof(dataToSend), reason);
    Cedapug_SendPostRequest(BAN_ENDPOINT, dataToSend, BanCallback);
}

void BanCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    char[] content = new char[response.ContentLength + 1];
    char[] message = new char[response.ContentLength + 1];
    response.GetContent(content, response.ContentLength + 1); 
    JSON_Object obj = json_decode(content);
    bool isBanned = obj.GetBool("isBanned");
    obj.GetString("message", message, response.ContentLength + 1);
    json_cleanup_and_delete(obj);
    
    if (isBanned)
    {
        CPrintToChatAll(message);
        CallCedapugBan();
        activePlayers.Clear();
    }
}

public void OnCedapugStarted(int regionArg)
{
    region = regionArg;
    GetActivePlayers();

    CreateTimer(TIME_DISCONNECT_CHECK, DisconnectCheck, 0, TIMER_REPEAT);

    if (currentNewGameTimer != INVALID_HANDLE)
    {
        CloseHandle(currentNewGameTimer);
        currentNewGameTimer = INVALID_HANDLE;
    }

    AddCommandListener(CallvoteKickCheck, "callvote");
}

public OnRoundIsLive()
{
    GetActivePlayers();
    isRoundLive = true;
    isReadyUp = false;
}

public Action Say_Callback(int client, const char[] command, int argc)
{
    SetEngineTime(client);
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if (IsHuman(client))
    {
        static int iLastMouse[MAXPLAYERS+1][2];
        
        // Mouse Movement Check
        if (mouse[0] != iLastMouse[client][0] || mouse[1] != iLastMouse[client][1])
        {
            iLastMouse[client][0] = mouse[0];
            iLastMouse[client][1] = mouse[1];
            SetEngineTime(client);
        }
        else if (buttons || impulse)
        {
            SetEngineTime(client);
        }
    }
    
    return Plugin_Continue;
}

void SetEngineTime(int client)
{
	g_fButtonTime[client] = GetEngineTime();
}

bool IsPlayerAfk(int client)
{
    if (isReadyUp)
    {
        return GetPlayingHumanCount() == 8 && !isPlayerReady[client] && IsPlayerAlive(client);
    }

    return !isPaused && IsPlayerAlive(client) && GetEngineTime() - g_fButtonTime[client] > AFK_DURATION;
}

public void OnPlayerReady(int client)
{
	isPlayerReady[client] = true;
}

public void OnPlayerUnready(int client)
{
	isPlayerReady[client] = false;
}

public void OnConfigsExecuted()
{
	OnReadyUp();
}

public void RoundStart_Event(Event event, const char[] name, bool dontBroadcast)
{
    OnReadyUp();
}

void OnReadyUp()
{
    SetAllPlayersUnready();
    isReadyUp = true;
}

void SetAllPlayersUnready()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		isPlayerReady[client] = false;
	}
}

Action CallCedapugBan()
{
    Action result;
    Call_StartForward(cedapugBanForward);
    Call_Finish(result);
}