#include <sourcemod>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

Address pCGameServer;

DynamicDetour CreateEntityByNameDetour;

int max_edictsOffset;

public Plugin myinfo = 
{
	name = "Edict Overflow Protection", 
	author = "KoNLiG", 
	description = "Useful tool to prevent edict overflow crashes in source engine games.", 
	version = "1.0.0", 
	url = "https://github.com/KoNLiG/EdictOverflowProtection"
};

public void OnPluginStart()
{
	GameData gamedata = new GameData("EdictOverflowProtection.games");
	
	if (!(pCGameServer = gamedata.GetAddress("pCGameServer")))
	{
		SetFailState("Failed to get 'pCGameServer' address");
	}
	
	if (!(max_edictsOffset = gamedata.GetOffset("CGameServer::max_edicts")))
	{
		SetFailState("Failed to get 'CGameServer::max_edicts' offset");
	}
	
	// Hook 'CreateEntityByName'.
	if (!(CreateEntityByNameDetour = new DynamicDetour(Address_Null, CallConv_CDECL, ReturnType_CBaseEntity, ThisPointer_Ignore)))
	{
		SetFailState("Failed to setup detour for 'CreateEntityByName'");
	}
	
	if (!CreateEntityByNameDetour.SetFromConf(gamedata, SDKConf_Signature, "CreateEntityByName"))
	{
		SetFailState("Failed to load 'CreateEntityByName' signature from gamedata");
	}
	
	// Add parameters
	CreateEntityByNameDetour.AddParam(HookParamType_CharPtr);
	CreateEntityByNameDetour.AddParam(HookParamType_Int);
	CreateEntityByNameDetour.AddParam(HookParamType_Bool);
	
	if (!CreateEntityByNameDetour.Enable(Hook_Pre, Detour_OnCreateEntityByName))
	{
		SetFailState("Failed to detour 'CreateEntityByName'");
	}
	
	delete gamedata;
}

// Replicate:
// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/engine/pr_edict.cpp#L151-L177
MRESReturn Detour_OnCreateEntityByName(DHookReturn hReturn, DHookParam hParams)
{
	// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/engine/vengineserver_impl.cpp#L667-L670
	int num_edicts = GetEntityCount();
	
	int max_edicts = LoadFromAddress(pCGameServer + view_as<Address>(max_edictsOffset), NumberType_Int32);
	
	if (num_edicts >= max_edicts)
	{
		if (max_edicts)
		{
			for (int current_edict = MaxClients + 1; current_edict < num_edicts; current_edict++)
			{
				if (GetEdictFlags(current_edict) & FL_EDICT_FREE)
				{
					return MRES_Ignored;
				}
			}
		}
		
		char classname[64];
		hParams.GetString(1, classname, sizeof(classname));
		
		LogError("Attemped to create an edict that will cause a server crash, aborted. (className: %s, iForceEdictIndex: %d, bNotify: %d)", classname, hParams.Get(2), hParams.Get(3));
		
		hReturn.Value = -1;
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
} 