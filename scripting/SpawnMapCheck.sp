#include <sourcemod>
#include <sdktools>

#define PL_VERSION "1.2"

public Plugin:myinfo = {
	name = "Spawns Map Check [SMC]",
	description = "Checks a map for enough spawn points.",
	author = "Roy (Christian Deacon)",
	version = PL_VERSION,
	url = "GFLClan.com & AlliedMods.net & TheDevelopingCommunity.com"
};

/*
	1.0:
		- Release
	1.1:
		- Added ConVar: "sm_SMC_mapcycle_pre" - When removing a map from the mapcycle, put this before the map (// will comment it out).
		- Added ConVar: "sm_SMC_mapcycle_post" - When removing a map from the mapcycle, put this after the map.
		- Added Option: Edited ConVar: "sm_SMC_newmap" - Switch to this map if the amount of spawns is under "sm_SMC_spawns"? (*blank* = no change, 0 = Get Next Map)
	1.2:
		- Organized code.
		- Fixed a potential memory leak.
		- Ready for AlliedMods release.
*/

// ConVars
new Handle:g_hSpawnPoints = INVALID_HANDLE;
new Handle:g_hMapCycle = INVALID_HANDLE;
new Handle:g_hMapCyclePre = INVALID_HANDLE;
new Handle:g_hMapCyclePost = INVALID_HANDLE;
new Handle:g_hLogMessage = INVALID_HANDLE;
new Handle:g_hNewMap = INVALID_HANDLE;
new Handle:g_hMapStartDelay = INVALID_HANDLE;
new Handle:g_hMapChangeDelay = INVALID_HANDLE;

// ConVar Vales
new g_iSpawnPoints;
new bool:g_bMapCycle;
new String:g_sMapCyclePre[256];
new String:g_sMapCyclePost[256];
new bool:g_bLogMessage;
new String:g_sNewMap[MAX_NAME_LENGTH];
new Float:g_fMapStartDelay;
new Float:g_fMapChangeDelay;

// Find ConVars
new Handle:g_hMapCyclePath;

// FindConVar Values
new String:g_sMapCyclePath[PLATFORM_MAX_PATH];

// Other
new iSpawnPoints;
new String:g_sNextMap[MAX_NAME_LENGTH];

public OnPluginStart() {
	// ConVars
	g_hSpawnPoints = CreateConVar("sm_SMC_spawns", "30", "How many spawns should we check for?");
	g_hMapCycle = CreateConVar("sm_SMC_mapcycle", "1", "Remove the map from the map cycle if the amount of spawns is under \"sm_SMC_spawns\"?");
	g_hMapCyclePre = CreateConVar("sm_SMC_mapcycle_pre", "//", "When removing a map from the mapcycle, put this before the map (// will comment it out).");
	g_hMapCyclePost = CreateConVar("sm_SMC_mapcycle_post", " Comment: Removed due to not enough spawns.", "When removing a map from the mapcycle, put this after the map.");
	g_hLogMessage = CreateConVar("sm_SMC_log", "1", "Log a SourceMod message if the amount of spawns is under \"sm_SMC_spawns\"?");
	g_hNewMap = CreateConVar("sm_SMC_newmap", "", "Switch to this map if the amount of spawns is under \"sm_SMC_spawns\"? (*blank* = no change, 0 = Get Next Map)");
	g_hMapStartDelay = CreateConVar("sm_SMC_mapstartdelay", "2.0", "The timer to check for spawns on OnMapStart();");
	g_hMapChangeDelay = CreateConVar("sm_SMC_mapchangedelay", "10.0", "Delay to switch the map if \"sm_SMC_newmap\" isn't blank and the amount of spawns is under \"sm_SMC_spawns\".");
	
	// AlliedMods Release
	CreateConVar("sm_SMC_version", PL_VERSION, "Spawns Map Check's plugin version");
	
	// Find ConVars
	g_hMapCyclePath = FindConVar("mapcyclefile");
	
	// Hook ConVar Changes
	HookConVarChange(g_hSpawnPoints, CVarChange);
	HookConVarChange(g_hMapCycle, CVarChange);
	HookConVarChange(g_hMapCyclePre, CVarChange);
	HookConVarChange(g_hMapCyclePost, CVarChange);
	HookConVarChange(g_hLogMessage, CVarChange);
	HookConVarChange(g_hNewMap, CVarChange);
	HookConVarChange(g_hMapStartDelay, CVarChange);
	HookConVarChange(g_hMapChangeDelay, CVarChange);
	HookConVarChange(g_hMapCyclePath, CVarChange);
	
	// Commands
	RegAdminCmd("sm_spawncheck", Command_SpawnCheck, ADMFLAG_ROOT);
	
	// Automatically Execute Config
	AutoExecConfig(true, "sm_SpawnsMapCheck");
}

public Action:Command_SpawnCheck(iClient, sArgs) {
	SpawnCheck();
	
	if (iClient != 0) {
		PrintToChat(iClient, " \x02[SMC] \x03Spawns has been checked. Results should be posted above this line.");
	} else {
		PrintToServer("[SMC] Spawns has been checked. Results should be posted above this line.");
	}
	
	return Plugin_Handled;
}

public CVarChange(Handle:hCVar, const String:sNewV[], const String:sOldV[]) {
	OnConfigsExecuted();
}

public OnConfigsExecuted() {
	g_iSpawnPoints = GetConVarInt(g_hSpawnPoints);
	g_bMapCycle = GetConVarBool(g_hMapCycle);
	GetConVarString(g_hMapCyclePre, g_sMapCyclePre, sizeof(g_sMapCyclePre));
	GetConVarString(g_hMapCyclePost, g_sMapCyclePost, sizeof(g_sMapCyclePost));
	g_bLogMessage = GetConVarBool(g_hLogMessage);
	GetConVarString(g_hNewMap, g_sNewMap, sizeof(g_sNewMap));
	g_fMapStartDelay = GetConVarFloat(g_hMapStartDelay);
	g_fMapChangeDelay = GetConVarFloat(g_hMapChangeDelay);
	GetConVarString(g_hMapCyclePath, g_sMapCyclePath, sizeof(g_sMapCyclePath));
}

public OnMapStart() {
	CreateTimer(g_fMapStartDelay, Timer_DelayOnMap);
}

public Action:Timer_DelayOnMap(Handle:timer) {
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
	
	if (iSpawnPoints < g_iSpawnPoints) {
		// Not enough spawns.
		
		decl String:sCurrentMap[MAX_NAME_LENGTH];
		GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
		
		if (g_bMapCycle) {
			decl String:sBuffer[255];
			decl String:sTPath[PLATFORM_MAX_PATH];
			decl String:sNPath[PLATFORM_MAX_PATH];
			new Handle:hCycleContents = CreateArray(256); 
			
			BuildPath(Path_SM, sTPath, sizeof(sTPath), "../../%s.new", g_sMapCyclePath);
			BuildPath(Path_SM, sNPath, sizeof(sNPath), "../../%s", g_sMapCyclePath);
			
			new Handle:hFileNewPath = OpenFile(sNPath, "r+");
			if (hFileNewPath != INVALID_HANDLE) {
				while (ReadFileLine(hFileNewPath, sBuffer, sizeof(sBuffer))) {
					ReplaceString(sBuffer, sizeof(sBuffer), "\n", "", false); 
					PushArrayString(hCycleContents, sBuffer);
				}
				
				CloseHandle(hFileNewPath);
			} else {
				LogError("[SMC]Failed to open original map cycle file: %s", sNPath);
			}
			
			new Handle:hFileTPath = OpenFile(sTPath, "w+");
			if (hFileTPath != INVALID_HANDLE) {
				decl String:sLine[64];
				decl String:sNewLine[64];
				for (new i = 0; i < GetArraySize(hCycleContents); i++) {
					// Write each map to the new mapcycle along with commenting the current map out.
					GetArrayString(hCycleContents, i, sLine, sizeof(sLine));
					if (StrEqual(sLine, sCurrentMap)) {
						Format(sNewLine, sizeof(sNewLine), "%s%s%s", g_sMapCyclePre, sLine, g_sMapCyclePost)
						WriteFileLine(hFileTPath, sNewLine);
					} else if (!StrEqual(sLine, "")) {
						WriteFileLine(hFileTPath, sLine);
					}
				}

				CloseHandle(hFileTPath);
			} else {
				LogError("[SMC]Failed to open map cycle file: %s", sTPath);
			}
			
			if (FileExists(sTPath)) {
				if (DeleteFile(sNPath)) {
					RenameFile(sNPath, sTPath);
				}
			}
			
			if (FileExists(sTPath)) {
				// Something must of went wrong.
				DeleteFile(sTPath);
			}
			
			if (hCycleContents != INVALID_HANDLE) {
				CloseHandle(hCycleContents);
			}
			
		}
		
		if (g_bLogMessage) {
			LogMessage("[SMC]%s does not have enough spawns %i/%i", sCurrentMap, iSpawnPoints, g_iSpawnPoints);
		}
		
		if (!StrEqual(g_sNewMap, "")) {
			if (StrEqual(g_sNewMap, "0")) {
				GetNextMap(g_sNextMap, sizeof(g_sNextMap));
			} else {
				strcopy(g_sNextMap, sizeof(g_sNextMap), g_sNewMap);
			}
			PrintToChatAll("\x02 [SMC] \x03Map does not have enough spawn points. Switching to %s in %f seconds", g_sNextMap, g_fMapChangeDelay);
			CreateTimer(g_fMapChangeDelay, Timer_SwitchMap);
		}
	}
}

public Action:Timer_SwitchMap(Handle:hTimer) {
	if (!StrEqual(g_sNextMap, "")) {
		ServerCommand("changelevel %s", g_sNextMap);
	}
}


