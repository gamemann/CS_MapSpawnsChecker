/****************************************************************************************************
[ANY] SPAWNS MAP CHECK
*****************************************************************************************************/

/****************************************************************************************************
CHANGELOG
*****************************************************************************************************
* 
* 1.0	     - 
* 
* 				First Release.
* 1.1	     - 
* 
* 				Added ConVar: sm_SMC_mapcycle_pre - When removing a map from the mapcycle, put this before the map (// will comment it out).
* 				Added ConVar: "sm_SMC_mapcycle_post" - When removing a map from the mapcycle, put this after the map.
* 				Added Option:  Edited ConVar: "sm_SMC_newmap" - Switch to this map if the amount of spawns is under "sm_SMC_spawns"? (*blank* = no change, 0 = Get Next Map)
* 1.2	     - 
*
* 				Cleanup, Port to new syntax (SM9).		
*/

/****************************************************************************************************
TO BE DONE
*****************************************************************************************************
* - Fixes / optimizations / suggestions..
*/

/****************************************************************************************************
INCLUDES
*****************************************************************************************************/
#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <multicolors>

/****************************************************************************************************
DEFINES
*****************************************************************************************************/
#define VERSION "1.2"

/****************************************************************************************************
ETIQUETTE.
*****************************************************************************************************/
#pragma newdecls required // To be moved before includes one day.
#pragma semicolon 1

/****************************************************************************************************
PLUGIN INFO.
*****************************************************************************************************/

public Plugin myinfo = 
{
	name = "Spawns Map Check [SMC][1.7]",
	description = "Checks a map for enough spawn points.",
	author = "[GFL] Roy (Christian Deacon) & SM9",
	version = VERSION,
	url = "http://GFLClan.com/topic/17536-any-spawns-map-check-version-10/"
};

/****************************************************************************************************
CONVAR HANDLES.
*****************************************************************************************************/
Handle hCvarSpawnPoints;
Handle hCvarMapCycle;
Handle hCvarMapCyclePost;
Handle hCvarLogMessage;
Handle hCvarMapCyclePre;
Handle hCvarNewMap;
Handle hCvarMapStartDelay;
Handle hCvarMapChangeDelay;
Handle hCvarMapCyclePath;
Handle hCvarTag;

/****************************************************************************************************
INTS.
*****************************************************************************************************/
int iCvarSpawnPoints;
int iSpawnPoints;

/****************************************************************************************************
STRINGS.
*****************************************************************************************************/
char chCvarNewMap[MAX_NAME_LENGTH];
char chCvarMapCyclePre[256];
char chCvarMapCyclePost[256];
char chCvarMapCyclePath[PLATFORM_MAX_PATH];
char chNextMap[MAX_NAME_LENGTH];
char chTag[64];

/****************************************************************************************************
BOOLEANS.
*****************************************************************************************************/
bool bCvarMapCycle;
bool bCvarLogMessage;

/****************************************************************************************************
FLOATS.
*****************************************************************************************************/
float fCvarMapStartDelay;
float fCvarMapChangeDelay;

public void OnPluginStart() 
{
	CreateConVars();
	UpdateVariables();
	RegAdminCmd("smc_spawncheck", CommandSpawnCheck, ADMFLAG_ROOT);
}

public void CreateConVars()
{
	AutoExecConfig_SetFile("spawnsmapcheck");
	hCvarMapCyclePath = FindConVar("mapcyclefile");
	hCvarSpawnPoints = AutoExecConfig_CreateConVar("smc_spawns", "32", "How many spawns should we check for?");
	hCvarMapCycle = AutoExecConfig_CreateConVar("smc_mapcycle", "1", "Remove the map from the map cycle if the amount of spawns is under \"sm_SMC_spawns\"?");
	hCvarMapCyclePre = AutoExecConfig_CreateConVar("smc_mapcycle_pre", "//", "When removing a map from the mapcycle, put this before the map (// will comment it out).");
	hCvarMapCyclePost = AutoExecConfig_CreateConVar("smc_mapcycle_post", " Comment: Removed due to not enough spawns.", "When removing a map from the mapcycle, put this after the map.");
	hCvarLogMessage = AutoExecConfig_CreateConVar("smc_log", "1", "Log a SourceMod message if the amount of spawns is under \"sm_SMC_spawns\"?");
	hCvarNewMap = AutoExecConfig_CreateConVar("smc_newmap", "", "Switch to this map if the amount of spawns is under \"sm_SMC_spawns\"? (*blank* = no change, 0 = Get Next Map)");
	hCvarMapStartDelay = AutoExecConfig_CreateConVar("smc_mapstartdelay", "2.0", "The timer to check for spawns on OnMapStart();");
	hCvarMapChangeDelay = AutoExecConfig_CreateConVar("smc_mapchangedelay", "5.0", "Delay to switch the map if \"sm_SMC_newmap\" isn't blank and the amount of spawns is under \"sm_SMC_spawns\".");
	hCvarTag = AutoExecConfig_CreateConVar("smc_tag", "{GREEN}[SMC]{DEFAULT}", "The tag which is used when printing messages (Can be changed to your own clan / community tag)");
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	HookConVarChange(hCvarSpawnPoints, OnCvarChanged);
	HookConVarChange(hCvarMapCycle, OnCvarChanged);
	HookConVarChange(hCvarMapCyclePre, OnCvarChanged);
	HookConVarChange(hCvarMapCyclePost, OnCvarChanged);
	HookConVarChange(hCvarLogMessage, OnCvarChanged);
	HookConVarChange(hCvarNewMap, OnCvarChanged);
	HookConVarChange(hCvarMapStartDelay, OnCvarChanged);
	HookConVarChange(hCvarMapChangeDelay, OnCvarChanged);
	HookConVarChange(hCvarMapCyclePath, OnCvarChanged);
}

public void UpdateVariables()
{
	/****************************************************************************************************
	INTS.
	*****************************************************************************************************/
	iCvarSpawnPoints = GetConVarInt(hCvarSpawnPoints);
	
	/****************************************************************************************************
	FLOATS.
	*****************************************************************************************************/
	fCvarMapStartDelay = GetConVarFloat(hCvarMapStartDelay);
	fCvarMapChangeDelay = GetConVarFloat(hCvarMapChangeDelay);
	/****************************************************************************************************
	BOOLS.
	*****************************************************************************************************/
	bCvarMapCycle = GetConVarInt(hCvarMapCycle) >= 1 ? true : false;
	bCvarLogMessage = GetConVarInt(hCvarLogMessage) >= 1 ? true : false;
	
	/****************************************************************************************************
	STRINGS.
	*****************************************************************************************************/
	GetConVarString(hCvarNewMap, chCvarNewMap, sizeof(chCvarNewMap));
	GetConVarString(hCvarMapCyclePre, chCvarMapCyclePre, sizeof(chCvarMapCyclePre));
	GetConVarString(hCvarMapCyclePost, chCvarMapCyclePost, sizeof(chCvarMapCyclePost));
	GetConVarString(hCvarMapCyclePath, chCvarMapCyclePath, sizeof(chCvarMapCyclePath));
	GetConVarString(hCvarTag, chTag, sizeof(chTag));
}

public Action CommandSpawnCheck(int iClient, int iArgs) 
{
	SpawnCheck();
	
	if(iClient != 0) 
	{
		CPrintToChat(iClient, "%s Spawns has been checked. Results should be posted above this line.", chTag);
	} 
	else 
	{
		PrintToServer("[SMC] Spawns has been checked. Results should be posted above this line.");
	}
	
	return Plugin_Handled;
}

public void OnCvarChanged(Handle hConvar, const char[] chOldValue, const char[] chNewValue) 
{
	UpdateVariables();
}

public void OnMapStart() 
{
	CreateTimer(fCvarMapStartDelay , DelayOnMap);
}

public Action DelayOnMap(Handle hTimer)
{
	SpawnCheck();
}

public void SpawnCheck() 
{
	iSpawnPoints = 0;
	
	char chClassName[MAX_NAME_LENGTH];
	char chCurrentMap[MAX_NAME_LENGTH];
	
	GetCurrentMap(chCurrentMap, sizeof(chCurrentMap));
	
	for(int i = 1; i <= GetMaxEntities(); i++) 
	{
		if(!IsValidEdict(i)) 
		{
			continue;
		}
		
		GetEdictClassname(i, chClassName, sizeof(chClassName));
		
		if (StrEqual(chClassName, "info_player_terrorist") || StrEqual(chClassName, "info_player_counterterrorist")) 
		{
			iSpawnPoints++;
		}
	}
	
	if(iSpawnPoints < iCvarSpawnPoints && bCvarMapCycle) 
	{
		char chBuffer[255];
		char chPath[PLATFORM_MAX_PATH];
		char chNewPath[PLATFORM_MAX_PATH];
	
		BuildPath(Path_SM, chPath, sizeof(chPath), "../../%s.new", chCvarMapCyclePath);
		BuildPath(Path_SM, chNewPath, sizeof(chNewPath), "../../%s", chCvarMapCyclePath);
		
		Handle hFileNewPath = OpenFile(chNewPath, "r+");
		Handle hCycleContents = CreateArray(256); 
		
		if(hFileNewPath != null) 
		{
			while(ReadFileLine(hFileNewPath, chBuffer, sizeof(chBuffer))) 
			{
				ReplaceString(chBuffer, sizeof(chBuffer), "\n", "", false); 
				PushArrayString(hCycleContents, chBuffer);
			}
			
			CloseHandle(hFileNewPath);
		} 
		
		else 
		{
			LogError("[SMC] Failed to open original map cycle file: %s", chNewPath);
		}
		
		Handle hFileTPath = OpenFile(chPath, "w+");
		
		if(hFileTPath != null) 
		{
			char chLine[64];
			char chNewLine[64];
			
			for(int i = 0; i < GetArraySize(hCycleContents); i++) 
			{
				GetArrayString(hCycleContents, i, chLine, sizeof(chLine));
				
				if(StrEqual(chLine, chCurrentMap)) 
				{
					Format(chNewLine, sizeof(chNewLine), "%s%s%s", hCvarMapCyclePre, chLine, hCvarMapCyclePost);
					WriteFileLine(hFileTPath, chNewLine);
				} 
				
				else if(!StrEqual(chLine, "")) 
				{
					WriteFileLine(hFileTPath, chLine);
				}
			}
			
			CloseHandle(hFileTPath);
		}
		
		else 
		{
			LogError("[SMC] Failed to open map cycle file: %s", chNewPath);
		}
		
		if(FileExists(chPath)) 
		{
			if(DeleteFile(chNewPath)) 
			{
				RenameFile(chNewPath, chPath);
			}
		}
		
		if(FileExists(chPath)) 
		{
			DeleteFile(chPath);
		}
		
	}
	
	if(bCvarLogMessage) 
	{
		LogMessage("[SMC] %s does not have enough spawns %i/%i", chCurrentMap, iSpawnPoints, iCvarSpawnPoints);
	}
	
	if(!StrEqual(chCvarNewMap, "")) 
	{
		if(StrEqual(chCvarNewMap, "0")) 
		{
			GetNextMap(chNextMap, sizeof(chNextMap));
		} 
		
		else 
		{
			strcopy(chNextMap, sizeof(chNextMap), chNextMap);
		}
		
		PrintToChatAll("%s Map does not have enough spawn points. Switching to %s in %f seconds", chTag, chNextMap, fCvarMapChangeDelay);
		CreateTimer(fCvarMapChangeDelay, SwitchMap);
	}
}

public Action SwitchMap(Handle hTimer) 
{
	if(!StrEqual(chNextMap, "")) 
	{
		ForceChangeLevel(chNextMap, "Not enough spawn points");
	}
}