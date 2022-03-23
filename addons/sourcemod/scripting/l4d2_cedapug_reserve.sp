#include <sourcemod>
#include <left4dhooks>
#include <json>
#include <l4d2_cedapug>

char RESERVE_ENDPOINT[] = "reserve";

public Plugin myinfo =
{
	name = "L4D2 CEDAPug Reserve",
	author = "Luckylock",
	description = "Reserves a server for CEDAPug games.",
	version = "2",
	url = "https://github.com/LuckyServ/"
};

public void OnPluginStart() {
    RegAdminCmd("sm_checkme", OnCheckMe, ADMFLAG_GENERIC);
}

Action OnCheckMe(int client, int args)
{
    ReserveCheck(client);
    return Plugin_Handled;
}

public void OnCedapugStarted(int regionArg)
{
    region = regionArg;
}

public void OnClientPutInServer(int client)
{
    ReserveCheck(client);
}

void ReserveCheck(int client)
{
    if (!IsHuman(client) || IS_CEDAPUG_GAME)
    {
        return;
    }

    char authId[MAX_STR_LEN];
    char playerOUTPUT[MAX_STR_LEN];
    char dataToSend[MAX_DATA_SIZE];
    GetClientAuthId(client, AuthId_SteamID64, authId, STEAMID_SIZE, false);

    JSON_Object playerJSON = new JSON_Object();
    playerJSON.SetInt("client", client);
    playerJSON.SetString("steamId", authId);
    playerJSON.Encode(playerOUTPUT, sizeof(playerOUTPUT));
    json_cleanup_and_delete(playerJSON);

    strcopy(dataToSend, sizeof(dataToSend), "data=");
    StrCat(dataToSend, sizeof(dataToSend), playerOUTPUT);
    Cedapug_SendPostRequest(RESERVE_ENDPOINT, dataToSend, ReserveCheckCallback);
}

void ReserveCheckCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    char[] content = new char[response.ContentLength + 1];
    response.GetContent(content, response.ContentLength + 1); 
    JSON_Object obj = json_decode(content);
    bool isPlayer = obj.GetBool("isPlayer");
    int client = obj.GetInt("client");
    json_cleanup_and_delete(obj);
    
    if (!isPlayer)
    {
        KickClient(client, "This server is reserved for CEDAPug games");
        RestartIfEmpty(client);
    }
}

void RestartIfEmpty(int client) {
    for (new i = 1; i <= MaxClients; ++i) {
        if (i != client && IsHuman(i)) {
            return;
        }
    }

    CreateTimer(0.1, CrashServer);
}


Action CrashServer(Handle timer)
{
    PrintToServer("L4D2 CEDAPug Reserve: Crashing the server...");
    SetCommandFlags("crash", GetCommandFlags("crash")&~FCVAR_CHEAT);
    ServerCommand("crash");

    return Plugin_Stop;
}