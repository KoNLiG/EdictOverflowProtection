#include <sourcemod>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define min(%1,%2)            (((%1) < (%2)) ? (%1) : (%2))
#define max(%1,%2)            (((%1) > (%2)) ? (%1) : (%2))
#define mclamp(%1,%2,%3)      min(max(%1,%2),%3)

DynamicDetour ED_FreeDetour;
DynamicDetour CreateEntityByNameDetour;

Address pCGameServer;

int num_edictsOffset;
int max_edicts;

public Plugin myinfo = 
{
	name = "Edict Overflow Protection", 
	author = "KoNLiG", 
	description = "Useful tool to prevent edict overflow crashes in source engine games.", 
	version = "1.1.4", 
	url = "https://github.com/KoNLiG/EdictOverflowProtection"
};

public void OnPluginStart()
{
	GameData gamedata = new GameData("EdictOverflowProtection.games");
	
	if (!(pCGameServer = gamedata.GetAddress("pCGameServer")))
	{
		SetFailState("Failed to get 'pCGameServer' address");
	}
	
	if ((num_edictsOffset = gamedata.GetOffset("CGameServer::num_edicts")) == -1)
	{
		SetFailState("Failed to get 'CGameServer::num_edicts' offset");
	}
	
	// Hook 'ED_Free'.
	if (!(ED_FreeDetour = new DynamicDetour(Address_Null, CallConv_CDECL, ReturnType_Void, ThisPointer_Ignore)))
	{
		SetFailState("Failed to setup detour for 'ED_Free'");
	}
	
	if (!ED_FreeDetour.SetFromConf(gamedata, SDKConf_Signature, "ED_Free"))
	{
		SetFailState("Failed to load 'ED_Free' signature from gamedata");
	}
	
	// Add parameters
	ED_FreeDetour.AddParam(HookParamType_Edict);
	
	if (!ED_FreeDetour.Enable(Hook_Pre, Detour_OnED_Free))
	{
		SetFailState("Failed to detour 'ED_Free'");
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
	
	max_edicts = GetMaxEntities();
}

MRESReturn Detour_OnED_Free(DHookParam hParams)
{
	int edict = hParams.Get(1);
	
	if (IsValidEdict(edict))
	{
		StoreToAddress(pCGameServer + view_as<Address>(num_edictsOffset), mclamp(LoadFromAddress(pCGameServer + view_as<Address>(num_edictsOffset), NumberType_Int32) - 1, MaxClients + 1, max_edicts), NumberType_Int32);
	}
	
	return MRES_Ignored;
}

// Replicate:
// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/engine/pr_edict.cpp#L151-L177
MRESReturn Detour_OnCreateEntityByName(DHookReturn hReturn, DHookParam hParams)
{
	// https://github.com/perilouswithadollarsign/cstrike15_src/blob/f82112a2388b841d72cb62ca48ab1846dfcc11c8/engine/vengineserver_impl.cpp#L667-L670
	int num_edicts = GetEntityCount();
	
	if (num_edicts >= max_edicts)
	{
		if (max_edicts)
		{
			for (int current_edict = MaxClients + 1; current_edict < num_edicts; current_edict++)
			{
				if (IsValidEdict(current_edict) && (GetEdictFlags(current_edict) & FL_EDICT_FREE))
				{
					return MRES_Ignored;
				}
			}
		}
		
		RequestFrame(Frame_ClearEdicts);
		
		char classname[64];
		hParams.GetString(1, classname, sizeof(classname));
		
		LogError("Attemped to create an edict that will cause a server crash, aborted. (className: %s, iForceEdictIndex: %d, bNotify: %d)", classname, hParams.Get(2), hParams.Get(3));
		
		// Return NULL or -1 can occasionally lead to random crashes.
		hReturn.Value = FindEntityByClassname(-1, classname);
		
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

void Frame_ClearEdicts()
{
	static int m_hOwnerEntityOffset;
	
	if (!m_hOwnerEntityOffset)
	{
		m_hOwnerEntityOffset = FindSendPropInfo("CBaseCombatWeapon", "m_hOwnerEntity");
	}
	
	char classname[64];
	
	for (int current_edict = MaxClients + 1, client; current_edict < max_edicts; current_edict++)
	{
		if (IsValidEdict(current_edict) // Validate the current edict
			 && GetEdictClassname(current_edict, classname, sizeof(classname)) // Store the edict classname
			 && (StrContains(classname, "weapon_") != -1 || StrContains(classname, "item_") != -1) // Filter the removal to weapons, items and chickens
			 && ((client = GetEntDataEnt2(current_edict, m_hOwnerEntityOffset)) == -1 || !ValidatePlayerWeapon(client, current_edict)))
		{
			// Removal
			RemoveEdict(current_edict);
		}
	}
}

bool ValidatePlayerWeapon(int client, int weapon)
{
	int max_weapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	
	for (int current_index; current_index < max_weapons; current_index++)
	{
		if (GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", current_index) == weapon)
		{
			return true;
		}
	}
	
	return false;
} 