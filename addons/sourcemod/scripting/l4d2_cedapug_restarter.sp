#include <sourcemod>
#include <left4dhooks>
#include <l4d2_cedapug>
#include <colors>

public Plugin myinfo =
{
	name = "L4D2 CEDAPug Restarter",
	author = "Luckylock",
	description = "Kicks everyone and restarts the server at the end of a cedapug game.",
	version = "3",
	url = "https://github.com/LuckyServ/"
};

public void OnCedapugEnded()
{
    // prevent compiler warning
    region = region + 0;

    CreateTimer(5.0, KickClientsAndRestartServer); 
}

Action KickClientsAndRestartServer(Handle timer, Handle hndl)
{
    for (new i = 1; i <= MaxClients; ++i) {
        if (IsHuman(i)) {
            KickClient(i, "The CEDAPug game has ended"); 
        }
    }

    CrashServer();
}

void CrashServer()
{
    PrintToServer("L4D2 CEDAPug Server Restarter: Crashing the server...");
    SetCommandFlags("crash", GetCommandFlags("crash")&~FCVAR_CHEAT);
    ServerCommand("crash");
}
