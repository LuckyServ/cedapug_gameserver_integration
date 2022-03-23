/**
 * Provides functionality to be able to send and get data to and from CEDAPug.
 *
 * Author: Luckylock
 */

#if defined _cedapug_included
 #endinput
#endif
#define _cedapug_included

#include <system2>
#include <json>
#include <colors>

#define MAX_STR_LEN 256
#define MAX_DATA_SIZE 1024
#define IS_CEDAPUG_GAME (region > 0)
#define STEAMID_SIZE 21
#define TEAM_SIZE 4

char SETTINGS_PATH[] = "data/cedapug_settings.txt";
char API_KEY_KEY[] = "apiKey";
char BASE_URL_KEY[] = "url";
char API_KEY_DATA_APPEND[] = "&apiKey="
char KV_NAME[] = "cedapug";
char API_KEY_PLACEHOLDER[] = "INSERT_API_KEY_HERE";
char BASE_URL_PLACEHOLDER[] = "https://cedapug.com/"
char regionPlayers[TEAM_SIZE * 2][STEAMID_SIZE];
char settingsFilePath[MAX_STR_LEN];
char apiKey[MAX_STR_LEN];
char baseUrl[MAX_STR_LEN];
int region;
KeyValues settings;
char regionNames[3][MAX_STR_LEN];

public void OnAllPluginsLoaded() {
    strcopy(regionNames[0], MAX_STR_LEN, "Novice");
    strcopy(regionNames[1], MAX_STR_LEN, "Intermediate");
    strcopy(regionNames[2], MAX_STR_LEN, "Expert");

    BuildPath(Path_SM, settingsFilePath, sizeof(settingsFilePath), SETTINGS_PATH);
    settings = CreateKeyValues(KV_NAME);

    if (!FileToKeyValues(settings, settingsFilePath)) {
        settings.SetString(API_KEY_KEY, API_KEY_PLACEHOLDER);
        settings.GotoNextKey(true);
        settings.SetString(BASE_URL_KEY, BASE_URL_PLACEHOLDER);
        KeyValuesToFile(settings, settingsFilePath);
    }

    KvGetString(settings, API_KEY_KEY, apiKey, sizeof(apiKey), API_KEY_PLACEHOLDER);
    KvGetString(settings, BASE_URL_KEY, baseUrl, sizeof(baseUrl), BASE_URL_PLACEHOLDER);
}

stock void Cedapug_SendPostRequest(char[] endpoint, char data[MAX_DATA_SIZE], System2HTTPResponseCallback callback) {
    char url[MAX_STR_LEN];
    GetUrlEndpoint(url, endpoint);
    AddApiKeyToData(data);

    System2HTTPRequest httpRequest = new System2HTTPRequest(callback, url);
    httpRequest.SetData(data);
    httpRequest.POST();
    delete httpRequest;
}

stock char[] AddApiKeyToData(char data[MAX_DATA_SIZE]) {
    char apiKeyData[MAX_STR_LEN];

    strcopy(apiKeyData, MAX_DATA_SIZE, API_KEY_DATA_APPEND);
    StrCat(apiKeyData, MAX_DATA_SIZE, apiKey);
    StrCat(data, MAX_DATA_SIZE, apiKeyData);

    return data;
}

stock char[] GetUrlEndpoint(char url[MAX_STR_LEN], char[] endpoint) {
    strcopy(url, MAX_STR_LEN, baseUrl);
    StrCat(url, MAX_STR_LEN, endpoint);

    return url;
}

stock int GetPlayingHumanCount()
{
    int humanCount = 0;

    for (new client = 1; client <= MaxClients; client++) {
        if (IsHumanPlaying(client)) {
            humanCount++;
        }
    }

    return humanCount;
}

stock void DefaultCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    if (!success) {
        LogError("Failed to connect to CEDAPug.");
    }
}

stock void PrintResponseCallback(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    char[] content = new char[response.ContentLength + 1];
    response.GetContent(content, response.ContentLength + 1); 
    CPrintToChatAll(content);
}

stock JSON_Array GetPlayers() {
    JSON_Array playersJSON = new JSON_Array();
    int playerCount = 0;

    for (new client = 1; client <= MaxClients; client++) {
        if (IsSurvivor(client) || IsInfected(client)) {
            GetClientAuthId(client, AuthId_SteamID64, regionPlayers[playerCount], STEAMID_SIZE, false);
            playersJSON.PushString(regionPlayers[playerCount]);
            playerCount++;
        }
    }

    return playersJSON;
}

stock bool:IsInFirstHalfOfRound()
{
    return !GameRules_GetProp("m_bInSecondHalfOfRound");
}

stock bool:IsSurvivor(client)                                                   
{                                                                               
    return IsHuman(client)
        && GetClientTeam(client) == 2; 
}

stock bool:IsInfected(client)                                                   
{                                                                               
    return IsHuman(client)
        && GetClientTeam(client) == 3; 
}

stock bool:IsHumanPlaying(client)
{
    return IsInfected(client) || IsSurvivor(client);
}

stock bool:IsHuman(client)                                                   
{                                                                               
    return client > 0 
        && client <= MaxClients 
        && IsClientInGame(client)
        && !IsFakeClient(client)
}
