#include <sourcemod>
#include <left4dhooks>
#include <sdktools>
#include <json>
#include <l4d2_cedapug>
#include <colors>

char rankData[MAX_DATA_SIZE];
char SCORE_KEY[] = "score";
char PLAYERS_KEY[] = "players"
char STEAMID_KEY[] = "steamId";
char REGION_KEY[] = "region";
char MAP_KEY[] = "map";
char NO_STEAMID[] = "NO_STEAMID";
char RANK_ENDPOINT[] = "rankdata";
char RANK_POST_KEY[] = "rankData=";
char MAP_NAME_BUFFER[30];
char playersFirstHalf[TEAM_SIZE][STEAMID_SIZE];
char playersSecondHalf[TEAM_SIZE][STEAMID_SIZE];
int scoreFirstHalf;
int scoreSecondHalf;
int initialScore;

int totalScoreFirstHalf = 0;
int totalScoreSecondHalf = 0;

bool isCedapugEnded = false;

public Plugin myinfo =
{
	name = "L4D2 CEDAPug Rank",
	author = "Luckylock",
	description = "Sends score and players data to cedapug each chapter.",
	version = "7",
	url = "https://github.com/LuckyServ/"
};

public void OnCedapugStarted(int regionArg)
{
    region = regionArg;
}

public void OnCedapugEnded()
{
    isCedapugEnded = true;

    if (totalScoreFirstHalf != 0 && totalScoreSecondHalf != 0)
    {
        SendRankData();
    }
}

public OnRoundIsLive() {
    if (IsInFirstHalfOfRound()) {
        Initialize();
        SavePlayers();
        totalScoreFirstHalf = GetCurrentSurvivorScore();
        totalScoreSecondHalf = GetCurrentInfectedScore();
    }

    initialScore = GetCurrentSurvivorScore();
}

public Action L4D2_OnEndVersusModeRound(bool:countSurvivors) 
{
    if (!isCedapugEnded)
    {
        CreateTimer(1.0, GetScoresAndSendData);
    }
    
    return Plugin_Continue;
}

public Initialize() {
    initialScore = 0;
    scoreFirstHalf = 0;
    scoreSecondHalf = 0;

    for (new i = 0; i < TEAM_SIZE; i++) {
        strcopy(playersFirstHalf[i], STEAMID_SIZE, NO_STEAMID);
        strcopy(playersSecondHalf[i], STEAMID_SIZE, NO_STEAMID);
    }

    for (new i = 0; i < TEAM_SIZE * 2; i++) {
        strcopy(regionPlayers[i], STEAMID_SIZE, NO_STEAMID);
    }
}

Action GetScoresAndSendData(Handle timer) {
    if (IsInFirstHalfOfRound()) {
        scoreFirstHalf = GetCurrentSurvivorScore() - initialScore;
    } else {
        scoreSecondHalf = GetCurrentSurvivorScore() - initialScore;
        totalScoreFirstHalf = GetCurrentInfectedScore();
        totalScoreSecondHalf = GetCurrentSurvivorScore();

        if (IS_CEDAPUG_GAME) {
            SendRankData();
        }
    }
}

int GetCurrentSurvivorScore() {
    if (L4D2_AreTeamsFlipped()) {
        return L4D2Direct_GetVSCampaignScore(1);
    } else {
        return L4D2Direct_GetVSCampaignScore(0);
    }
}

int GetCurrentInfectedScore()
{
    if (L4D2_AreTeamsFlipped()) {
        return L4D2Direct_GetVSCampaignScore(0);
    } else {
        return L4D2Direct_GetVSCampaignScore(1);
    }
}

void SendRankData() {
    JSON_Array rankJSON = BuildRankJSON();
    rankJSON.Encode(rankData, sizeof(rankData));
    json_cleanup_and_delete(rankJSON);

    char dataToSend[MAX_DATA_SIZE];
    strcopy(dataToSend, sizeof(dataToSend), RANK_POST_KEY);
    StrCat(dataToSend, sizeof(dataToSend), rankData);
    Cedapug_SendPostRequest(RANK_ENDPOINT, dataToSend, DefaultCallback);
}

void SavePlayers() {
    int playerCountFirstHalf = 0;
    int playerCountSecondHalf = 0;

    for (new client = 1; client <= MaxClients; client++) {
        if (IsSurvivor(client) && playerCountFirstHalf < TEAM_SIZE) {
            GetClientAuthId(client, AuthId_SteamID64, playersFirstHalf[playerCountFirstHalf], STEAMID_SIZE, false);
            playerCountFirstHalf++;
        } else if (IsInfected(client) && playerCountSecondHalf < TEAM_SIZE) {
            GetClientAuthId(client, AuthId_SteamID64, playersSecondHalf[playerCountSecondHalf], STEAMID_SIZE, false);
            playerCountSecondHalf++;
        }
    }
}

JSON_Array BuildRankJSON() {
    JSON_Array rankJSON = new JSON_Array();
    JSON_Object dataInfo = new JSON_Object();
    JSON_Object dataFirstHalf = new JSON_Object();
    JSON_Object dataSecondHalf = new JSON_Object();
    GetCurrentMap(MAP_NAME_BUFFER, 29);

    BuildTeamObject(dataFirstHalf, isCedapugEnded ? totalScoreFirstHalf : scoreFirstHalf, playersFirstHalf);
    BuildTeamObject(dataSecondHalf, isCedapugEnded ? totalScoreSecondHalf : scoreSecondHalf, playersSecondHalf);
    dataInfo.SetInt(REGION_KEY, region);
    dataInfo.SetString(MAP_KEY, MAP_NAME_BUFFER);
    dataInfo.SetBool("isGameEnd", isCedapugEnded);

    rankJSON.PushObject(dataInfo);
    rankJSON.PushObject(dataFirstHalf);
    rankJSON.PushObject(dataSecondHalf);

    return rankJSON;
}

void BuildTeamObject(JSON_Object teamData, int score, char[][] players) {
    teamData.SetInt(SCORE_KEY, score);
    JSON_Array playersData = new JSON_Array();

    for (new i = 0; i < TEAM_SIZE; i++) {
        JSON_Object player = new JSON_Object();
        player.SetString(STEAMID_KEY, players[i]);
        playersData.PushObject(player);
    }

    teamData.SetObject(PLAYERS_KEY, playersData);
}