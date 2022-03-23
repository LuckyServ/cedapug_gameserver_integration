#include <sourcemod>
#include <json>
#include <l4d2_cedapug>
#include <left4dhooks>
#include <colors>

int SURVIVORS = 0;
int INFECTED = 1;
char MAP_NAME_BUFFER[30];

public Plugin myinfo =
{
    name = "L4d2 CEDAPug Sub",
    author = "H0tacos, Luckylock",
    description = "This plugin provide sub integration with cedapug.",
    version = "2",
    url = "https://cedapug.com/"
};

public void OnCedapugStarted(int regionArg)
{
    region = regionArg;
}

public void OnPluginStart() {
    RegConsoleCmd("sm_sub", OnSubCommand);    
}

Action OnSubCommand(int client, int args){
    if (!IS_CEDAPUG_GAME)
    {
        return Plugin_Handled;
    }

    char playerIdAndIp[MAX_DATA_SIZE];
    JSON_Object playerData = CreateJsonSub(client);
    playerData.Encode(playerIdAndIp, sizeof(playerIdAndIp));
    json_cleanup_and_delete(playerData);

    //PrintToChatAll("We are currently improving the sub functionnality. This command might not work properly for the next few hours. We apologize for the inconvenience.");

    char dataToSend[MAX_DATA_SIZE];
    strcopy(dataToSend, sizeof(dataToSend), "subData=");
    StrCat(dataToSend, sizeof(dataToSend), playerIdAndIp);
    Cedapug_SendPostRequest("asksub", dataToSend, PrintResponseCallback);

    return Plugin_Handled;
}


/*TODO:
test if team score is correct. -> ok
test if json return right values. ->ok*/
JSON_Object CreateJsonSub(int client) {
    JSON_Object player = new JSON_Object();
    char  steamId[STEAMID_SIZE];
    char server_port[10];
    int scores[2] = 0; 
    char teamScoreStr[2][5];

    new Handle:cvar_port = FindConVar("hostport");
    GetConVarString(cvar_port, server_port, sizeof(server_port));
    CloseHandle(cvar_port);

    GetClientAuthId(client, AuthId_SteamID64, steamId, STEAMID_SIZE, false);
    GetCurrentMap(MAP_NAME_BUFFER, 29);
    L4D2_GetVersusCampaignScores(scores);
    IntToString(scores[0], teamScoreStr[0], 5);
    IntToString(scores[1], teamScoreStr[1], 5);

    player.SetString("steamId", steamId); 
    player.SetString("port", server_port);
    player.SetString("map", MAP_NAME_BUFFER);

    if (GetClientTeam(client) == SURVIVORS) {
        player.SetString("TeamScore", teamScoreStr[SURVIVORS]);
        player.SetString("EnemyTeamScore", teamScoreStr[INFECTED]);
    } else { //player is an infected
        player.SetString("TeamScore", teamScoreStr[INFECTED]);
        player.SetString("EnemyTeamScore", teamScoreStr[SURVIVORS]);
    }
    return player;
}