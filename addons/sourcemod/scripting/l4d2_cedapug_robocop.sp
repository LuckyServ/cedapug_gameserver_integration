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
int THRESHOLD_GAME_ENDED = 120;

// Threhold for banning a player
int THRESHOLD_BAN = 240;

/* STARTBAN POLICY */
Handle currentNewGameTimer = INVALID_HANDLE;
bool isRoundLive = false;

/* ENDPOINTS */
char PLAYERS_POST_KEY[] = "players=";
char BAN_ENDPOINT[] = "ban";
char START_BAN_ENDPOINT[] = "startban";
char allPlayers[64][STEAMID_SIZE];

/* CONSTANTS */
char REASON_GAME_LEFT[MAX_STR_LEN] = "GAME_LEFT";

public Plugin myinfo =
{
    name = "L4d2 CEDAPug Robocop",
    author = "Luckylock",
    description = "Provides automatic moderation for cedapug.",
    version = "6",
    url = "https://cedapug.com/"
};

public void OnPluginStart() {
    RegAdminCmd("sm_startban", OnStartBan, ADMFLAG_GENERIC); 
    activePlayers = CreateTrie();
    currentNewGameTimer = CreateTimer(480.0, NewGameCreatedTookTooLong);
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

            if (disconnectCount > THRESHOLD_GAME_ENDED)
            {
                gameEndedCount++;
            }

            if (disconnectCount > THRESHOLD_BAN) {
                activePlayers.Remove(steamId);
                playersToBan.PushString(steamId);
            }
        }
    }

    if (gameEndedCount >= 3)
    {
        activePlayers.Clear();
    }
    else
    {
        for (int i = 0; i < playersToBan.Length; i++)
        {
            playersToBan.GetString(i, steamId, STEAMID_SIZE);
            BanPlayer(steamId, REASON_GAME_LEFT);
        }
    }

    delete playersToBan; 
    delete snapshot;

    return Plugin_Continue;
}

bool IsSteamIdPlaying(const char[] steamId)
{
    if (strlen(steamId) == 0)
    {
        return false;
    }

    char authId[MAX_STR_LEN];

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHuman(client))
        {
            GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);

            if (StrEqual(steamId, authId) && IsHumanPlaying(client))
            {
                return true;
            }
        }
    }

    return false;
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

void BanPlayer(const char[] steamId, const char[] reason)
{
    char dataToSend[MAX_DATA_SIZE];
    strcopy(dataToSend, sizeof(dataToSend), "steamId=");
    StrCat(dataToSend, sizeof(dataToSend), steamId);
    StrCat(dataToSend, sizeof(dataToSend), "&reason=");
    StrCat(dataToSend, sizeof(dataToSend), reason);
    Cedapug_SendPostRequest(BAN_ENDPOINT, dataToSend, PrintResponseCallback);
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
}