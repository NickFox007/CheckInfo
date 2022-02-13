/* ==================================================================================================
										Changelog
							
	1.0 - Первая полноценная версия плагина
	
	1.1 - Возможность вызова из админ-меню
		- Новый формат выдачи данных
		- Старый формат сохранён и доступен через команду sm_checkall (!checkall)
		- Понемногу покручиваем конфигурацию плагина и логику работы при отсутствии
		зависимых плагинов
		
	1.2 - Приведение кода в более презентабельный вид при помощи @Grey83
		(https://hlmod.ru/members/grey83.38839/)
		- Фиксы для работы в CS:S - подгон под размеры чата и отключение проверки Прайма
		в автоматическом режиме
		- Настройка функциональности через конфиг-файл (cfg/sourcemod/sm_checkinfo.cfg)
		- Пофикшено неполучение идентификатора BHOP из магазина
		после первой загрузки плагина
		- Теперь плагин работает без проблем даже если не установлено ядро VIP или SHOP
		
  1.2.1 - HOTFIX 
		- Исправлены наименования в админ-меню
		- Переработана проверка наличия зависимых плагинов	

	1.3 - Теперь основной функционал будет вынесен в отдельную библиотеку, поэтому ничего не мешает
		использовать её вместе с другими плагинами при желании
		- Фикс кривого считывания типа SteamID из конфига
		- Добавлена настройка выбора показа SteamID или IP игрока по команде !checkall (sm_checkall)
		в конфиг файле
		- Добавлена проверка наличия VAC статуса
		- Добавлена проверка Steam/NoSteam
		
	1.4 - Теперь SteamWorks необязателен, но рекомендуется для возможности получения Prime-статуса
		- Изменил метод получения идентификатора BHOP из SHOP. Теперь он обновляется каждые 30 секунд
		- Теперь идентификатор BHOP для VIP указывается в конфиге (sm_checkinfo_vipbhop)
		- Фикс загрузки конфига
		- Другие мелкие фиксы

	1.5 - Убрана "лишняя" отладочная надпись BHOP
		- Более в конфиге указывать название способности из VIP не требуется (жестко прописаны две используемые на серверах)
		- Теперь боту GOTV периодически выписывается информация об игроках
		- Загрузка "на горячую" отображает верный статус Steam/NoSteam
   ================================================================================================== */

#pragma dynamic 131072 


#include <sdktools_stringtables>
#include <colors>
#include <cf_core>

#undef REQUIRE_PLUGIN

#tryinclude <adminmenu>

#pragma semicolon 1
#pragma newdecls required


AuthIdType iSIDType = AuthId_Steam2; // Для хранения типа SteamID, который нужно получать

int IPIDType_ID = 1; // Переменная для значения sm_checkinfo_viewipidtype

char polosa[51]; // Для хранения текста ПОЛОСКИ

// Идентификатор для взаимодействия с админ-меню
TopMenu	g_hTopMenu;

Handle g_Cvarsid = INVALID_HANDLE;
Handle g_Cvaripid = INVALID_HANDLE;
//Handle g_Cvarvb = INVALID_HANDLE;
//Хэндлы для конваров


public Plugin myinfo = 
{
	name		= "CheckInfo",
	version		= "1.5",
	description	= "Get some players' info. Получение определённой информации об игроках.",
	author		= "NickFox",
	url			= "https://vk.com/nf_dev"
}

public void OnPluginStart()
{	
	g_Cvarsid = CreateConVar("sm_checkinfo_steamid", "1", "SteamID-Type in !check/!checkall [1 - STEAM_1:1:1234 | 2 - [U:1:1234] | 3 - 76512345678900000]", _, true, 1.0, true, 3.0);
	g_Cvaripid = CreateConVar("sm_checkinfo_viewipidtype", "1", "SteamID/IP-address in !checkall [1 - IP | 2 - SteamID]", _, true, 1.0, true, 2.0);
	//g_Cvarvb = CreateConVar("sm_checkinfo_vipbhop", "BHOP", "BHOP's ID for VIP-core [String value]");
	
	HookConVarChange(g_Cvarsid,OnSteamTypeChange);
	HookConVarChange(g_Cvaripid,OnIPIDTypeChange);
	//HookConVarChange(g_Cvarvb,OnVIPBHOPChange);
	// Создаём КВары для настройки и обработчики их изменения
	
	RegConsoleCmd("sm_check", Cmd_Check);
	RegConsoleCmd("sm_checkall", Cmd_CheckAll);
	
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
	// Регистрация команд
	
	if(GetEngineVersion() == Engine_CSGO)
	// Для правильного вмещения ограничительной полосы по ширине чата
	// в зависимости от версии игры (CS:GO/Другая), а также рентабельности проверки Прайма 
	{
		polosa="============================================";
	}
	else
	{
		polosa="=================================";
	}
		
	
	if(LibraryExists("adminmenu"))
	{
		TopMenu hTopMenu;
		if((hTopMenu = GetAdminTopMenu())) OnAdminMenuReady(hTopMenu);
	}

	AutoExecConfig(true, "sm_checkinfo");
	
	for(int i = 1; i < MAXPLAYERS; i++) if(IsClientConnected(i)) OnClientPutInServer(i);
	
	//ChangeSteamIDType();
	CF_Init();
}

Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i < MAXPLAYERS; i++) if(IsClientSourceTV(i))
	{
		Cmd_CheckAll(i, 0); 
		break;
	}
}

public void OnConfigsExecuted()
{
	ChangeSteamIDType(GetConVarInt(g_Cvarsid));
	IPIDType_ID = GetConVarInt(g_Cvaripid);
	//g_Cvarvb.GetString(VIP_BHOP,sizeof(VIP_BHOP));	  
	//GetConVarString(g_Cvarvb,VIP_BHOP,sizeof(VIP_BHOP));


}

void OnIPIDTypeChange(ConVar convar, const char[] oldValue, const char[] newValue){
	// Если значение переменной "sm_checkinfo_viewipidtype" изменилось - подхватить его
	IPIDType_ID = convar.IntValue;
}

void ChangeSteamIDType(int iSIDType_ID){
	// Изменить тип выводимого SteamID
	switch(iSIDType_ID)
	{
		case 1:	iSIDType = AuthId_Steam2;
		case 2:	iSIDType = AuthId_Steam3;
		case 3:	iSIDType = AuthId_SteamID64;
	}
}

void OnSteamTypeChange(ConVar convar, const char[] oldValue, const char[] newValue){
	// Если значение переменной "sm_checkinfo_steamid" изменилось - подхватить его
	ChangeSteamIDType(convar.IntValue);	
}

/*
void OnVIPBHOPChange(ConVar convar, const char[] oldValue, const char[] newValue){
	// Если значение переменной "sm_checkinfo_vipbhop" изменилось - подхватить его
	convar.GetString(VIP_BHOP,sizeof(VIP_BHOP));	
}
*/

public void OnLibraryAdded(const char[] szName) 
{   
	CF_OnLibraryON(szName); // Для перехвата события библиотекой

}

public void OnLibraryRemoved(const char[] szName) 
{  	
	CF_OnLibraryOFF(szName); // Для перехвата события библиотекой
	if(StrEqual(szName, "adminmenu"))
		g_hTopMenu = null;

}


public void OnClientPutInServer(int client){
	CF_PlayerConnected(client); // Для перехвата события библиотекой
}


void DisplayCheckInfoMenu(int client) // Функция показа меню с выбором игрока
{
	Menu menu = new Menu(MenuHandler_CheckPlayerInfo); // Прикрепляем обработчик при выборе в категории
	menu.SetTitle("Выбрать игрока"); // Устанавливаем заголовок
	menu.ExitBackButton = true; // Активируем кнопку выхода	
	AddTargetsToMenu(menu, client, true, false); // Добавляем игроков в меню выбора
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CheckPlayerInfo(Menu menu, MenuAction action, int client, int param2)
{
	if(action == MenuAction_End)
		delete menu; // Выход из меню
	else if(action == MenuAction_Select) // Если игрок был выбран
	{
		char info[8];
		int target;
		menu.GetItem(param2, info, sizeof(info));
		if((target = GetClientOfUserId(StringToInt(info))) && !IsFakeClient(target)) PrintInfo(target,client);
		DisplayCheckInfoMenu(client);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack && g_hTopMenu)
		g_hTopMenu.Display(client, TopMenuPosition_LastCategory); // Вернуться в предыдущую категорию
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu hTopMenu = TopMenu.FromHandle(aTopMenu);
	if(hTopMenu == g_hTopMenu) return;

	g_hTopMenu = hTopMenu;
	TopMenuObject hMyCategory = g_hTopMenu.FindCategory(ADMINMENU_PLAYERCOMMANDS);
	if(hMyCategory == INVALID_TOPMENUOBJECT) return;

	// Теперь можем добавить пункты
	g_hTopMenu.AddItem("checkinfo_menu", Handler_MenuCheck, hMyCategory, "sm_check", ADMFLAG_GENERIC, "CheckInfo");
/*
*	"checkinfo_menu"	- уникальное имя пункта
*	Handler_MenuCheck	- обработчик событий
*	hMyCategory			- Объект категории в которую должен быть добавлен пункт
*	"sm_check"			- команда(для access overrides)
*	ADMFLAG_GENERIC		- Флаг доступа по умолчанию(изначально - b)
*	"CheckInfo"			- Описание пункта(опционально)
*/
}

// обработчик событий категории админ-меню
public void Handler_MenuCheck(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:	FormatEx(sBuffer, maxlength, "Инфо об игроке"); // Когда категория отображается пунктом на главной странице админ-меню
		case TopMenuAction_DisplayTitle:	FormatEx(sBuffer, maxlength, "Выбрать игрока"); // Когда категория отображается заглавием текущего меню
		case TopMenuAction_SelectOption:	DisplayCheckInfoMenu(iClient); // Показываем меню выбора игрока
	}
}


public Action PrintInfo(int i, int client)
{
	char buffer[MAX_NAME_LENGTH];
	CPrintToChat(client, polosa); // Полоса
	GetClientName(i, buffer, sizeof(buffer));
	if (prime_ingame) CPrintToChat(client, "[%u] {lime}%s {grey}[%s{grey}] %s", i, buffer,
	CF_CheckPrime(i) ? "{green}Prime" : "{darkred}NoPrime", CF_GetVAC(i) ? "{darkred}VAC" : " "); // Вывод ID, ника, VAC и Прайм-статуса (если CS:GO)
	
	else CPrintToChat(client, "[%u] {lime}%s {grey} %s", i, buffer,
	CF_GetVAC(i) ? "{darkred}VAC" : " "); // Вывод всего, кроме Прайм-статуса (в ином случае)
	
	GetClientAuthId(i, iSIDType, buffer, sizeof(buffer)); // Получение SteamID
	CPrintToChat(client, "%s - {orange}%s",CF_GetIsSteam(i) ? "{olive}SteamID" : "{darkred}NoSteamID", buffer); // Вывод SteamID/NoSteamID
	GetClientIP(i, buffer, sizeof(buffer)); // Получение IP
	CPrintToChat(client, "{olive}IP - {orange}%s", buffer); // Вывод IP
	if(IsShopExist||IsVIPExist){
	
		switch(CF_CheckBhop(i))
		{
			case 2:	buffer ="{green}VIP";	//Включен ли Бхоп в меню VIP
			case 1:	buffer ="{green}SHOP";	//Куплен ли и активирован BHOP в инвентаре магазина
			default:buffer ="{darkred}NONE";// Если BHOP не имеется
		}
		CPrintToChat(client, "{olive}BHOP - %s", buffer); // Вывод данных о BHOP
	}
	CPrintToChat(client, polosa); // Полоса
	//PrintToChat(client,VIP_BHOP);
}

public Action Cmd_Check(int client, int args) // sm_check | !check
{
	if(!client) return Plugin_Handled;

	//Проверка наличия админ-флага(по умолчанию - b). При отсутствии флага у игрока выведет сообщение о несуществующей команде
	if(!CheckCommandAccess(client, "BypassPremiumCheck", ADMFLAG_GENERIC, true))
		return Plugin_Continue;

	DisplayCheckInfoMenu(client); // Показываем админ-меню
	return Plugin_Handled;
}

public Action Cmd_CheckAll(int client, int args) // sm_checkall | !checkall
{
	if(!client) return Plugin_Handled;

	//Проверка наличия админ-флага(по умолчанию - b). При отсутствии флага у игрока выведет сообщение о несуществующей команде
	if(!IsClientSourceTV(client) && !CheckCommandAccess(client, "BypassPremiumCheck", ADMFLAG_GENERIC, true))
		return Plugin_Continue;   

	for(int i= 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i)) GetPlayerInfo(client, i);
	return Plugin_Handled;
}

public void GetPlayerInfo(int client, int target)
{
	char name[MAX_NAME_LENGTH], bhop[12], client_ipid[32], prime_status[26];


	switch(CF_CheckBhop(target))
	{
		case 2:	bhop ="[VIP-BHOP]";
		case 1:	bhop ="[SHOP-BHOP]";
	}
	
	switch(IPIDType_ID)
	{
		case 1:	GetClientIP(target, client_ipid, sizeof(client_ipid)); // Получение IP игрока
		case 2:	GetClientAuthId(target, iSIDType, client_ipid, sizeof(client_ipid)); // Получение SteamID
	}	
	GetClientName(target, name, sizeof(name));

	if (prime_ingame) prime_status = CF_CheckPrime(target) ? "[{green}Prime{grey}] " : "[{darkred}NoPrime{grey}] ";	
	else prime_status = "";
	CPrintToChat(client, "[%u] {lime}%s {grey}%s{olive}%s {lime}%s%s%s",
		target, name, prime_status, client_ipid, bhop, CF_GetVAC(target) ? " {darkred}VAC" : " ",CF_GetIsSteam(target) ? "" : " {darkred}NoSteam");
	
}