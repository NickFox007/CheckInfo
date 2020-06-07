/*	Список функций
 *	
 *	CF_CheckBhop(int client) - возвращает значение int для игрока client (0 - нет BHOP, 1 - SHOP, 2 - VIP)
 *	CF_CheckPrime(int client) - возвращает значение bool для игрока client (true - куплен Prime, false - не куплен Prime)
 *	CF_GetVAC(int client) - возвращает значение bool для игрока client (true - есть VAC-бан, false - нет VAC-бана)
 *	CF_GetIsSteam(int client) - возвращает значение bool для игрока client (true - Steam, false - NoSteam)
 *	
 *
 *	Для корректной работы необходимо обеспечить перенаправление некоторых событий из плагина в библиотеку
 *	
 *	Пример:
 

public void OnPluginStart()
{	
	CF_Init(); // Для перехвата события библиотекой
}

public void OnLibraryAdded(const char[] szName) 
{   
	CF_OnLibraryON(szName); // Для перехвата события библиотекой
}


public void OnLibraryRemoved(const char[] szName) 
{  	
	CF_OnLibraryOFF(szName); // Для перехвата события библиотекой
}
 
 
public void OnClientPutInServer(int client)
{
	CF_PlayerConnected(client); // Для перехвата события библиотекой
}


 *
 *
 */


#undef REQUIRE_PLUGIN

#tryinclude <adminmenu>
#tryinclude <vip_core>
#tryinclude <shop>

#undef REQUIRE_EXTENSIONS
#tryinclude <SteamWorks>

bool IsVIPExist = false; // Статус наличия ядра VIP
bool IsShopExist = false; // Статус наличия ядра SHOP

ItemId g_iID; // Для хранения идентификатора BHOP в базе магазина

bool prime_ingame; // Для вывода наличия/отсутствия прайма

bool bVAC[65]; // Для хранения VAC-статуса
bool bClientSteam[65]; // Для хранения состояния Steam/NoSteam

// Идентификатор BHOP в VIP-системе. Если отличается от имеющегося - изменить
char VIP_BHOP[64] = "BHOP1";

#define STEAMWORKS_ON()	(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SteamWorks_CreateHTTPRequest")	== FeatureStatus_Available)

public void CF_Init()
{
	prime_ingame=false;
		
#if defined _SteamWorks_Included	
	if(GetEngineVersion() == Engine_CSGO)
	// Для правильного вмещения ограничительной полосы по ширине чата
	// в зависимости от версии игры (CS:GO/Другая), а также рентабельности проверки Прайма 
	{
		prime_ingame=true;
	}
#endif
	CreateTimer(30.0, Timer_GetShopID, _, TIMER_REPEAT);
}


public Action Timer_GetShopID(Handle timer){

	getShopID();
	return Plugin_Continue;

}

public void getShopID(){

	if(IsShopExist)
	g_iID = Shop_GetItemId(Shop_RegisterCategory("ability", "Способности", ""),"shop_bhop"); // Получаем ИД Бхопа в магазине

}


public void CF_PlayerConnected(int client)
{ // Если игрок присоединился

	if(!IsFakeClient(client)){
	
		if (STEAMWORKS_ON()) CF_CheckVAC(client); // Обновляем VAC-статус игрока
	
	}

}


public int CF_CheckBhop(int i)
{
	if(IsVIPExist&&VIP_IsClientFeatureUse(i, VIP_BHOP)) //Включен ли Бхоп в меню VIP 
			return 2;

	if(IsShopExist&&Shop_IsClientItemToggled(i, g_iID)) //Включен ли Бхоп в меню SHOP 
		return 1;

	return 0;
}

public void CF_OnLibraryOFF(const char[] szName) 
{    // Если ядра были выгружены
	if(StrEqual(szName, "vip_core")) // VIP
		IsVIPExist = false;
	if(StrEqual(szName, "shop")) // SHOP
		IsShopExist = false;

}

public void CF_OnLibraryON(const char[] szName) 
{	// Если ядра были загружены
	if(StrEqual(szName, "vip_core")) // VIP
		IsVIPExist = true;
	if(StrEqual(szName, "shop")) // SHOP
		IsShopExist = true;
}

public bool CF_CheckPrime(int client) // Проверка на купленный Прайм
{
	if (STEAMWORKS_ON()) return k_EUserHasLicenseResultDoesNotHaveLicense != SteamWorks_HasLicenseForApp(client, 624820);
	else return false;
}

#if defined _SteamWorks_Included

public bool CF_GetVAC(client)
{
	return bVAC[client]; // Возвращаем уже определённое значение VAC-бана
}

public bool CF_GetIsSteam(client)
{
	return bClientSteam[client]; // Возвращаем уже определённое значение Steam/NoSteam
}

public void CF_CheckVAC(client)
{	// Обновляет наличие VAC-бана у игрока
	char sURL[70];
	char sSteamID[20];
	bVAC[client] = false;
	GetClientAuthId(client, AuthId_SteamID64, sSteamID, 20);
	FormatEx(sURL, 70, "https://steamcommunity.com/profiles/%s?xml=1", sSteamID);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, sURL);
	SteamWorks_SetHTTPCallbacks(hRequest, CF_OnSteamWorksHTTPComplete);
	SteamWorks_SetHTTPRequestContextValue(hRequest, client);
	SteamWorks_SendHTTPRequest(hRequest);
}



void CF_OnSteamWorksHTTPComplete(Handle:hRequest, bool:bFailure, bool:bRequestSuccessful, EHTTPStatusCode:eStatusCode, any:client)
{	// Проверка успешности запроса
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK) SteamWorks_GetHTTPResponseBodyCallback(hRequest, CF_SteamWorksHTTPBodyCallback, client);
	
	CloseHandle(hRequest);
}

void CF_SteamWorksHTTPBodyCallback(const String:sData[], any:client)
{	// Если ответ от сайта был получен
	if(StrContains(sData, "<profile>", false) != -1) 
	{
		bClientSteam[client] = true;
		
		if(StrContains(sData, "<vacBanned>0</vacBanned>", false) == -1) bVAC[client] = true;
		else bVAC[client] = false;
			
	}
	else
	{
		bClientSteam[client] = false;
	}
}
#endif
