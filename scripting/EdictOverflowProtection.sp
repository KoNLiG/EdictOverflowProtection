#include <sourcemod>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

DynamicDetour CreateEntityByNameDetour;

int max_edicts;

public Plugin myinfo = 
{
	name = "Edict Overflow Protection", 
	author = "KoNLiG", 
	description = "Useful tool to prevent edict overflow crashes in source engine games.", 
	version = "1.1.", 
	url = "https://github.com/KoNLiG/EdictOverflowProtection"
};

public void OnPluginStart()
{
	GameData gamedata = new GameData("EdictOverflowProtection.games");
	
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