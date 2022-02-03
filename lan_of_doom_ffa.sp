#include <sdkhooks>
#include <sourcemod>

public const Plugin myinfo = {
    name = "Free For All", author = "LAN of DOOM",
    description = "Enables free for all scoring and damage", version = "1.0.0",
    url = "https://github.com/lanofdoom/counterstrike-free-for-all"};

static const int kMoneyLostPerTeamkill = 3600;
static const int kFragsLostPerTeamkill = 1;
static const float kTeammateDamageFraction = 0.35;

static ConVar g_friendlyfire_cvar;
static int g_account_offset;

//
// Logic
//

static bool IsTeamKill(int attacker, int victim) {
  return attacker != 0 && GetClientTeam(attacker) == GetClientTeam(victim);
}

//
// Hooks
//

static Action OnTakeDamage(int victim, int& attacker, int& inflictor,
                           float& damage, int& damagetype) {
  if (!GetConVarBool(g_friendlyfire_cvar)) {
    return Plugin_Continue;
  }

  if (!IsTeamKill(victim, attacker)) {
    return Plugin_Continue;
  }

  damage /= kTeammateDamageFraction;
  return Plugin_Changed;
}

static Action OnMessage(UserMsg msg_id, BfRead msg, const int[] players,
                        int num_players, bool reliable, bool init) {
  if (!GetConVarBool(g_friendlyfire_cvar)) {
    return Plugin_Continue;
  }

  char message[PLATFORM_MAX_PATH];
  BfReadString(msg, message, PLATFORM_MAX_PATH);

  if (StrContains(message, "careful_around_teammates") != -1 ||
      StrContains(message, "Killed_Teammate") != -1 ||
      StrContains(message, "spotted_a_friend") != -1 ||
      StrContains(message, "teammate_attack") != -1 ||
      StrContains(message, "try_not_to_injure_teammates") != -1) {
    return Plugin_Handled;
  }

  return Plugin_Continue;
}

static Action OnPlayerDeath(Handle event, const char[] name,
                            bool dontBroadcast) {
  if (!GetConVarBool(g_friendlyfire_cvar)) {
    return Plugin_Continue;
  }

  int victim = GetEventInt(event, "userid");
  if (!victim) {
    return Plugin_Continue;
  }

  int victim_client = GetClientOfUserId(victim);
  if (!victim_client) {
    return Plugin_Continue;
  }

  int attacker = GetEventInt(event, "attacker");
  if (!attacker) {
    return Plugin_Continue;
  }

  int attacker_client = GetClientOfUserId(attacker);
  if (!attacker_client) {
    return Plugin_Continue;
  }

  if (!IsTeamKill(victim, attacker)) {
    return Plugin_Continue;
  }

  int current_frags = GetClientFrags(attacker);
  SetEntProp(attacker, Prop_Data, "m_iFrags",
             current_frags + kFragsLostPerTeamkill);

  int current_account = GetEntData(attacker, g_account_offset);
  SetEntData(attacker, g_account_offset,
             current_account + kMoneyLostPerTeamkill);

  return Plugin_Continue;
}

//
// Forwards
//

public void OnClientPutInServer(int client) {
  SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnPluginStart() {
  g_friendlyfire_cvar = FindConVar("mp_friendlyfire");

  g_account_offset = FindSendPropInfo("CCSPlayer", "m_iAccount");

  UserMsg text_msg = GetUserMessageId("TextMsg");
  UserMsg hint_text = GetUserMessageId("HintText");

  if (!g_friendlyfire_cvar || g_account_offset == -1 ||
      text_msg == INVALID_MESSAGE_ID || hint_text == INVALID_MESSAGE_ID) {
    ThrowError("Initialization failed");
  }

  HookEvent("player_death", OnPlayerDeath);

  HookUserMessage(text_msg, OnMessage, true);
  HookUserMessage(hint_text, OnMessage, true);

  for (new client = 1; client <= MaxClients; client++) {
    if (!IsClientInGame(client)) {
      continue;
    }

    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
  }
}