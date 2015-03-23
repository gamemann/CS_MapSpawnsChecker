#include <sourcemod>
#include <sdktools>

public Plugin:myinfo = {
	name = "Spawns Map Check [SMC]",
	description = "Checks a map for enough spawn points.",
	author = "[GFL] Roy (Christian Deacon)",
	version = "1.1",
	url = "http://GFLClan.com/topic/17536-any-spawns-map-check-version-10/"
};

/*
	1.0:
		- Release
	1.1:
		- Added ConVar: "sm_SMC_mapcycle_pre" - When removing a map from the mapcycle, put this before the map (// will comment it out).
		- Added ConVar: "sm_SMC_mapcycle_post" - When removing a map from the mapcycle, put this after the map.
		- Added Option: Edited ConVar: "sm_SMC_newmap" - Switch to this map if the amount of spawns is under "sm_SMC_spawns"? (*blank* = no change, 0 = Get Next Map)
*/

// ConVar and ConVar values.
new Handle:g_cvarSpawnPoints = INVALID_HANDLE;
new icvarSpawnPoints;
new Handle:g_cvarMapCycle = INVALID_HANDLE;
new bool:bcvarMapCycle;
new Handle:g_cvarMapCyclePre = INVALID_HANDLE;
new String:scvarMapCyclePre[256];
new Handle:g_cvarMapCyclePost = INVALID_HANDLE;
new String:scvarMapCyclePost[256];
new Handle:g_cvarLogMessage = INVALID_HANDLE;
new bool:bcvarLogMessage;
new Handle:g_cvarNewMap = INVALID_HANDLE;
new String:scvarNewMap[MAX_NAME_LENGTH];
new Handle:g_cvarMapStartDelay = INVALID_HANDLE;
new Float:fcvarMapStartDelay;
new Handle:g_cvarMapChangeDelay = INVALID_HANDLE;
new Float:fcvarMapChangeDelay;

new Handle:g_cvarMapCyclePath;
new String:scvarMapCyclePath[PLATFORM_MAX_PATH];
new String:nextmap[MAX_NAME_LENGTH];

// Values
new iSpawnPoints;

public OnPluginStart() {
	g_cvarSpawnPoints = CreateConVar("sm_SMC_spawns", "30", "How many spawns should we check for?");
	g_cvarMapCycle = CreateConVar("sm_SMC_mapcycle", "1", "Remove the map from the map cycle if the amount of spawns is under \"sm_SMC_spawns\"?");
	g_cvarMapCyclePre = CreateConVar("sm_SMC_mapcycle_pre", "//", "When removing a map from the mapcycle, put this before the map (// will comment it out).");
	g_cvarMapCyclePost = CreateConVar("sm_SMC_mapcycle_post", " Comment: Removed due to not enough spawns.", "When removing a map from the mapcycle, put this after the map.");
	g_cvarLogMessage = CreateConVar("sm_SMC_log", "1", "Log a SourceMod message if the amount of spawns is under \"sm_SMC_spawns\"?");
	g_cvarNewMap = CreateConVar("sm_SMC_newmap", "", "Switch to this map if the amount of spawns is under \"sm_SMC_spawns\"? (*blank* = no change, 0 = Get Next Map)");
	g_cvarMapStartDelay = CreateConVar("sm_SMC_mapstartdelay", "2.0", "The timer to check for spawns on OnMapStart();");
	g_cvarMapChangeDelay = CreateConVar("sm_SMC_mapchangedelay", "5.0", "Delay to switch the map if \"sm_SMC_newmap\" isn't blank and the amount of spawns is under \"sm_SMC_spawns\".");
	
	g_cvarMapCyclePath = FindConVar("mapcyclefile");
	
	HookConVarChange(g_cvarSpawnPoints, CVarChange);
	HookConVarChange(g_cvarMapCycle, CVarChange);
	HookConVarChange(g_cvarMapCyclePre, CVarChange);
	HookConVarChange(g_cvarMapCyclePost, CVarChange);
	HookConVarChange(g_cvarLogMessage, CVarChange);
	HookConVarChange(g_cvarNewMap, CVarChange);
	HookConVarChange(g_cvarMapStartDelay, CVarChange);
	HookConVarChange(g_cvarMapChangeDelay, CVarChange);
	HookConVarChange(g_cvarMapCyclePath, CVarChange);
	
	RegAdminCmd("sm_spawncheck", Command_SpawnCheck, ADMFLAG_ROOT);
	
	AutoExecConfig(true, "sm_SMC");
}

public Action:Command_SpawnCheck(client, args) {
	SpawnCheck();
	
	if (client != 0) {
		PrintToChat(client, " \x02[SMC] \x03Spawns has been checked. Results should be posted above this line.");
	} else {
		PrintToServer("[SMC] Spawns has been checked. Results should be posted above this line.");
	}
	
	return Plugin_Handled;
}

public CVarChange(Handle:convar, const String:newv[], const String:oldv[]) {
	OnConfigsExecuted();
}

public OnConfigsExecuted() {
	icvarSpawnPoints = GetConVarInt(g_cvarSpawnPoints);
	bcvarMapCycle = GetConVarBool(g_cvarMapCycle);
	GetConVarString(g_cvarMapCyclePre, scvarMapCyclePre, sizeof(scvarMapCyclePre));
	GetConVarString(g_cvarMapCyclePost, scvarMapCyclePost, sizeof(scvarMapCyclePost));
	bcvarLogMessage = GetConVarBool(g_cvarLogMessage);
	GetConVarString(g_cvarNewMap, scvarNewMap, sizeof(scvarNewMap));
	fcvarMapStartDelay = GetConVarFloat(g_cvarMapStartDelay);
	fcvarMapChangeDelay = GetConVarFloat(g_cvarMapChangeDelay);
	GetConVarString(g_cvarMapCyclePath, scvarMapCyclePath, sizeof(scvarMapCyclePath));
}

public OnMapStart() {
	CreateTimer(fcvarMapStartDelay, DelayOnMap);
}

public Action:DelayOnMap(Handle:timer) {
	SpawnCheck();
}

stock SpawnCheck() {
	iSpawnPoints = 0;
	decl String:sClassName[MAX_NAME_LENGTH];
	
	for (new i = 1; i <= GetMaxEntities(); i++) {
		if (!IsValidEdict(i)) {
			continue;
		}
		
		GetEdictClassname(i, sClassName, sizeof(sClassName));
		
		if (StrEqual(sClassName, "info_player_terrorist")) {
			iSpawnPoints++;
		} else if (StrEqual(sClassName, "info_player_counterterrorist")) {
			iSpawnPoints++;
		}
	}
	
	if (iSpawnPoints < icvarSpawnPoints) {
		// Not enough spawns.
		
		decl String:currentmap[MAX_NAME_LENGTH];
		GetCurrentMap(currentmap, sizeof(currentmap));
		
		if (bcvarMapCycle) {
			decl String:buffer[255];
			decl String:tpath[PLATFORM_MAX_PATH];
			decl String:newp[PLATFORM_MAX_PATH];
			new Handle:cyclecontents = CreateArray(256); 
			
			BuildPath(Path_SM, tpath, sizeof(tpath), "../../%s.new", scvarMapCyclePath);
			BuildPath(Path_SM, newp, sizeof(newp), "../../%s", scvarMapCyclePath);
			
			new Handle:fileNewPath = OpenFile(newp, "r+");
			if (fileNewPath != INVALID_HANDLE) {
				while (ReadFileLine(fileNewPath, buffer, sizeof(buffer))) {
					ReplaceString(buffer, sizeof(buffer), "\n", "", false); 
					PushArrayString(cyclecontents, buffer);
				}
				
				CloseHandle(fileNewPath);
			} else {
				LogError("[SMC]Failed to open original map cycle file: %s", newp);
			}
			
			new Handle:fileTPath = OpenFile(tpath, "w+");
			if (fileTPath != INVALID_HANDLE) {
				decl String:sLine[64];
				decl String:newsLine[64];
				for (new i = 0; i < GetArraySize(cyclecontents); i++) {
					// Write each map to the new mapcycle along with commenting the current map out.
					GetArrayString(cyclecontents, i, sLine, sizeof(sLine));
					if (StrEqual(sLine, currentmap)) {
						Format(newsLine, sizeof(newsLine), "%s%s%s", scvarMapCyclePre, sLine, scvarMapCyclePost)
						WriteFileLine(fileTPath, newsLine);
					} else if (!StrEqual(sLine, "")) {
						WriteFileLine(fileTPath, sLine);
					}
					
					// LogMessage("[SMC]%s", sLine); -- Debugging only.
				}

				CloseHandle(fileTPath);
			} else {
				LogError("[SMC]Failed to open map cycle file: %s", tpath);
			}
			
			if (FileExists(tpath)) {
				if (DeleteFile(newp)) {
					RenameFile(newp, tpath);
				}
			}
			
			if (FileExists(tpath)) {
				// Something must of went wrong.
				DeleteFile(tpath);
			}
			
		}
		
		if (bcvarLogMessage) {
			LogMessage("[SMC]%s does not have enough spawns %i/%i", currentmap, iSpawnPoints, icvarSpawnPoints);
		}
		
		if (!StrEqual(scvarNewMap, "")) {
			if (StrEqual(scvarNewMap, "0")) {
				GetNextMap(nextmap, sizeof(nextmap));
			} else {
				strcopy(nextmap, sizeof(nextmap), scvarNewMap);
			}
			PrintToChatAll("\x02 [SMC] \x03Map does not have enough spawn points. Switching to %s in %f seconds", nextmap, fcvarMapChangeDelay);
			CreateTimer(fcvarMapChangeDelay, SwitchMap);
		}
	}
}

public Action:SwitchMap(Handle:timer) {
	if (!StrEqual(nextmap, "")) {
		ServerCommand("changelevel %s", nextmap);
	}
}


