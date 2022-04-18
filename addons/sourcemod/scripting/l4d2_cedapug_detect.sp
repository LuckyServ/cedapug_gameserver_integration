#include <sourcemod>
#include <left4dhooks>
#include <sdktools>
#include <json>
#include <l4d2_cedapug>

char REGION_ENDPOINT[] = "gameregionmap";
char REGION_POST_KEY[] = "players=";
bool checkedCedapugGame = false;
StringMap currentPlayers;
bool isCedapugEnded = false;
Handle hGameRuleOngoingCeda;
Handle hGameRuleCedaLevel;

public Plugin myinfo =
{
    name = "L4D2 CEDAPug Detect",
    author = "Luckylock",
    description = "Detects the start of a CEDAPug game.",
    version = "4",
    url = "https://github.com/LuckyServ/"
};

GlobalForward cedapugStartedForward;
GlobalForward cedapugEndedForward;

public void OnPluginStart()
{
    cedapugStartedForward = new GlobalForward("OnCedapugStarted", ET_Event, Param_Cell);
    cedapugEndedForward = new GlobalForward("OnCedapugEnded", ET_Event, Param_Cell);

    HookEvent("player_disconnect", OnPlayerDisconnectEvent);

    RegAdminCmd("sm_disconnectme", OnDisconnectMe, ADMFLAG_GENERIC);

    hGameRuleOngoingCeda = CreateConVar("l4d2_cedapug_active", "0", "1 - if there is ongoin Ceda game, 0 - if not. Will be added to public server rules. Does not have any effect on anything, needed for statistical purposes", FCVAR_NOTIFY);
    hGameRuleCedaLevel = CreateConVar("l4d2_cedapug_level", "none", "The values are Novice, Intermediate, or Expert. Will be added to public server rules. Does not have any effect on anything, needed for statistical purposes", FCVAR_NOTIFY);
    HookEvent("server_cvar", EventCvarChanged, EventHookMode_Pre);
}

Action OnDisconnectMe(int client, int args)
{
    HandlePlayerDisconnected(client);
}

public Action OnPlayerDisconnectEvent(Handle:event, const String:name[], bool:dontBroadcast) 
{
    decl String:networkID[22];
    GetEventString(event, "networkid", networkID, sizeof(networkID));
    if (StrContains(networkID, "BOT", false) != -1) return;

    HandlePlayerDisconnected(GetClientOfUserId(GetEventInt(event, "userid", 0)));
}

void HandlePlayerDisconnected(int client)
{
    if (!IS_CEDAPUG_GAME)
    {
        return;
    }

    char authId[MAX_STR_LEN];
    GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);
    currentPlayers.SetValue(authId, true, true);

    currentPlayers.Remove(authId);

    if (currentPlayers.Size <= 3 && !isCedapugEnded)
    {
        CPrintToChatAll("{green}CEDAPug: {default}Game ended.");
        isCedapugEnded = true;
        CreateTimer(5.0, CallCedapugEnded);
        SetConVarInt(hGameRuleOngoingCeda, 0);
    }
}

void PopulateCurrentPlayers()
{
    currentPlayers = CreateTrie();
    char authId[MAX_STR_LEN];

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHuman(client)) {
            GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);
            currentPlayers.SetValue(authId, true, true);
        }
    }
}

public void OnClientPutInServer(int client)
{
    if (!IS_CEDAPUG_GAME || !IsHuman(client))
    {
        return;
    }

    char authId[MAX_STR_LEN];
    GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);
    currentPlayers.SetValue(authId, true, true);
}

public OnRoundIsLive() {
    if (!checkedCedapugGame) {
        CheckCedapugGame();
        checkedCedapugGame = true;
    }
}

void CheckCedapugGame() {
    char playersData[MAX_DATA_SIZE];
    char mapBuffer[100];

    JSON_Object playersJSON = new JSON_Object();
    JSON_Array playersARRAY = GetPlayers();
    GetCurrentMap(mapBuffer, 100);
    playersJSON.SetString("map", mapBuffer);
    playersJSON.SetObject("players", playersARRAY);

    playersJSON.Encode(playersData, sizeof(playersData));
    json_cleanup_and_delete(playersJSON);
    char dataToSend[MAX_DATA_SIZE];
    strcopy(dataToSend, sizeof(dataToSend), REGION_POST_KEY);
    StrCat(dataToSend, sizeof(dataToSend), playersData);

    Cedapug_SendPostRequest(REGION_ENDPOINT, dataToSend, GetRegionCallback);
    delete playersJSON;
}

void GetRegionCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    if (success) {
        char[] content = new char[response.ContentLength + 1];
        response.GetContent(content, response.ContentLength + 1);
        region = StringToInt(content);

        if (IS_CEDAPUG_GAME) {
            CPrintToChatAll("{green}CEDAPug: {default}Game started ({olive}%s{default})", regionNames[region - 1]);
            SetConVarString(hGameRuleCedaLevel, regionNames[region - 1]);
            SetConVarInt(hGameRuleOngoingCeda, 1);
            CallCedapugStarted();
        } else if (region == -10) {
            CPrintToChatAll("{green}CEDAPug: {default}Game started on the wrong map ({olive}Unranked{default})");
        }
        // else
        // {
        //     CPrintToChatAll("{green}CEDAPug: {default}Game started ({olive}%s{default})", "TESTING NO REGION");
        //     region = 1;
        //     CallCedapugStarted();
        // }
    }
} 

public void OnCedapugStarted(int regionArg)
{
    PopulateCurrentPlayers();
}

public void OnCedapugEnded()
{
    // Nothing
}

void CallCedapugStarted()
{
    Action result;
    Call_StartForward(cedapugStartedForward);
    Call_PushCell(region);
    Call_Finish(result);
}

Action CallCedapugEnded(Handle timer, Handle hndl)
{
    Action result;
    Call_StartForward(cedapugEndedForward);
    Call_Finish(result);
}

Action EventCvarChanged(Event event, const char[] name, bool dontBroadcast)
{
    char sBuffer[32];
    GetEventString(event, "cvarname", sBuffer, sizeof(sBuffer), "none");
    if (StrEqual(sBuffer, "l4d2_cedapug_active") || StrEqual(sBuffer, "l4d2_cedapug_level")) {
        event.BroadcastDisabled = true;
    }
    return Plugin_Continue;
}
