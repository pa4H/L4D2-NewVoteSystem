#include <sourcemod>
#include <sdktools>
#include <colors>

#define L4D2_TEAM_ALL        -1 // ID всех команд
#define L4D2_TEAM_SPECTATORS 1  // ID наблюдателей
#define L4D2_TEAM_SURVIVORS  2  // ID выживших
#define L4D2_TEAM_INFECTED   3  // ID зараженных

Handle g_AllTalkCvar; // Переменная для взаимодействия с sv_alltalk

int count_YesVotes; // Количество голосов ЗА
int count_NoVotes; // Количество голосов ПРОТИВ
int playersCount; // Количество игроков способных голосовать
bool VoteInProgress; // Если true, то голосование проводится
bool CanPlayerVote[MAXPLAYERS + 1]; // False если игрок проголосовал

char argOne[MAXPLAYERS + 1][64]; // Первый аргумент из консоли
char argTwo[MAXPLAYERS + 1][64]; // Второй аргумент из консоли

int voteInTeam; // Сюда пишется номер тимы где будет происходить голосование
char callerName[MAXPLAYERS + 1][32]; // Имя игрока начавшего голосование
char voteName[128]; // Название голсования
char votePassAnswer[128]; // Ответ на состоявшееся голосование (текст)
char buferArgument[64]; // Буферная переменная для хранения 1 аргумента
char buferArgument2[64]; // Буферная переменная для хранения 2 аргумента
char mapForChange[64]; // Переменная для хранения названия карты для смены
char txtBufer[256]; // Буферная переменная для форматирования текста
char PREFIX[16]; // Переменная для хранения префикса
native void L4D2_ChangeLevel(const char[] sMap); // Нужен плагин changelevel.smx (для корректной смены карты)

Handle g_hTimer; // Для убийства таймера обязательно нужно создавать его через Handle
Handle map_Timer; 
public Plugin:myinfo = 
{
	name = "[L4D2] New Vote System", 
	author = "pa4H", 
	description = "New vote system for L4D2", 
	version = "1.0", 
	url = "vk.com/pa4h1337"
}


public OnPluginStart()
{
	RegConsoleCmd("sm_customvote", customVote, "Usage: sm_customvote <Text> <Text after PASS vote>");
	
	RegAdminCmd("sm_pass", voteYes, ADMFLAG_BAN);
	RegAdminCmd("sm_veto", voteNo, ADMFLAG_BAN);
	
	RegConsoleCmd("sm_kickspec", kickSpecVote, "");
	RegConsoleCmd("sm_sk", kickSpecVote, "");
	RegConsoleCmd("sm_ks", kickSpecVote, "");
	RegConsoleCmd("sm_nospec", kickSpecVote, "");
	
	RegConsoleCmd("sm_killbots", kickInfectedBotsVote, "");
	RegConsoleCmd("sm_kb", kickInfectedBotsVote, "");
	
	RegConsoleCmd("sm_voterestart", restartChapterVote, "");
	RegConsoleCmd("sm_restart", restartChapterVote, "");
	RegConsoleCmd("sm_rematch", restartChapterVote, "");
	
	RegConsoleCmd("Vote", vote); // Обработчик команды Vote (Vote Yes; Vote No)
	AddCommandListener(Listener_CallVote, "callvote"); // Обработчик команды callvote
	
	LoadTranslations("pa4HNewVoteSystem.phrases"); // Загружаем тексты всех фраз
	LoadTranslations("pa4HNewVoteSystemMaps.phrases"); // Загружаем названия карт
	
	FormatEx(PREFIX, sizeof(PREFIX), "%t", "PREFIX");
}

public Action customVote(int client, int args)
{
	if (args != 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_customVote <Text> <Text after PASS vote>");
		return Plugin_Handled;
	}
	GetCmdArg(1, argOne[client], sizeof(argOne[]));
	GetCmdArg(2, argTwo[client], sizeof(argTwo[]));
	createVote(client, L4D2_TEAM_ALL);
	return Plugin_Handled;
}

public Action restartChapterVote(int client, int args)
{
	FakeClientCommandEx(client, "callvote RestartChapter"); // Вызываем рестарт карты
	return Plugin_Handled;
}

public Action kickSpecVote(int client, int args)
{
	
	FormatEx(argOne[client], sizeof(argOne[]), "KickSpec"); // Вписываем в аргумент1 название кастомного голосования
	createVote(client, L4D2_TEAM_ALL);
	FormatEx(txtBufer, sizeof(txtBufer), "%t", "KickSpec", PREFIX, callerName[client]); // Получаем перевод и формируем строку
	CPrintToChatAll(txtBufer); // "{1} {2} голосует за исключение зрителей!"
	
	return Plugin_Continue;
}

public Action kickInfectedBotsVote(int client, int args)
{
	
	if (GetClientTeam(client) == 3)
	{
		FormatEx(argOne[client], sizeof(argOne[]), "KillInfectedBots"); // Вписываем в аргумент1 название кастомного голосования
		createVote(client, L4D2_TEAM_INFECTED);
		
		for (int x = 1; x <= MaxClients; x++) // Пишем только в чат зараженных
		{
			if (IsValidClient(x) && GetClientTeam(x) == 3)
			{
				FormatEx(txtBufer, sizeof(txtBufer), "%t", "KillInfectedBots", PREFIX, callerName[client]); // Получаем перевод и формируем строку
				CPrintToChat(x, txtBufer); // "{1} {2} голосует за убийство ботов"
			}
		}
	}
	else
	{
		FormatEx(txtBufer, sizeof(txtBufer), "%t", "NoKillInfectedBots", PREFIX); // Получаем перевод и формируем строку
		CPrintToChat(client, txtBufer); // "Только команда зараженных может использовать эту команду"
	}
	return Plugin_Continue;
}

public Action Listener_CallVote(client, const String:command[], argc)
{
	if (!VoteInProgress)
	{
		GetCmdArg(1, argOne[client], sizeof(argOne[])); // Получаем 1 аргумент
		GetCmdArg(2, argTwo[client], sizeof(argTwo[])); // Получаем 2 аргумент
		GetClientName(client, callerName[client], sizeof(callerName[])); // Получаем ник игрока
		
		// ReturnToLobby
		if (StrEqual(argOne[client], "ReturnToLobby", false)) // Если вызвали голосование ReturnToLobby
		{
			for (new x = 1; x <= MaxClients; x++)
			{
				if (IsClientInGame(x) && !IsFakeClient(x))
				{
					if (client == x) // Пишем в чат вызывающего голосование
					{
						FormatEx(txtBufer, sizeof(txtBufer), "%t", "ReturnToLobby1", PREFIX); // Получаем перевод и формируем строку
						CPrintToChat(x, txtBufer); // "{1} Нельзя выходить в лобби!"
					}
					else // Пишем в общий чат
					{
						FormatEx(txtBufer, sizeof(txtBufer), "%t", "ReturnToLobby2", PREFIX, callerName[client]); // Получаем перевод и формируем строку
						CPrintToChat(x, txtBufer); // "{1} Тупой дебил {2} попытался выйти в лобби"
					}
				}
			}
		}
		
		// AllTalk
		if (StrEqual(argOne[client], "ChangeAllTalk", false))
		{
			g_AllTalkCvar = FindConVar("sv_alltalk"); // Обращаемся к sv_alltalk
			if (GetConVarInt(g_AllTalkCvar)) // Если Alltalk включен (sv_alltalk 1)
			{
				FormatEx(txtBufer, sizeof(txtBufer), "%t", "ChangeAllTalkOff", PREFIX, callerName[client]); // Turn off ALLTalk?
			}
			else
			{
				FormatEx(txtBufer, sizeof(txtBufer), "%t", "ChangeAllTalkOn", PREFIX, callerName[client]); // Turn on ALLTalk?
			}
			CPrintToChatAll(txtBufer); // "{1} {2} голосует за включение общего чата!"
			createVote(client, L4D2_TEAM_ALL);
		}
		
		// ChangeChapter
		if (StrEqual(argOne[client], "ChangeChapter", false))
		{
			char txtBufer2[128];
			FormatEx(txtBufer2, sizeof(txtBufer2), "%t", argTwo[client]); // Получаем вместо c8m1_apartments Нет милосердию: 1.Апартаменты
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "ChangeChapter", PREFIX, callerName[client], txtBufer2); // Получаем перевод и формируем строку
			CPrintToChatAll(txtBufer); // "{1} {2} голосует за смену карты на {3}"
			createVote(client, L4D2_TEAM_ALL);
		}
		// ChangeMission
		if (StrEqual(argOne[client], "ChangeMission", false)) // В аргументе вместо c8m1_apartments передается L4D2C8
		{
			char txtBufer2[128];
			FormatEx(txtBufer2, sizeof(txtBufer2), "%t", argTwo[client]); // Получаем вместо L4D2C8 Нет милосердию: 1.Апартаменты
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "ChangeChapter", PREFIX, callerName[client], txtBufer2); // Получаем перевод и формируем строку
			CPrintToChatAll(txtBufer); // "{1} {2} голосует за смену карты на {3}"
			createVote(client, L4D2_TEAM_ALL);
		}
		
		// Kick
		if (StrEqual(argOne[client], "Kick", false))
		{
			int g_client = GetClientOfUserId(StringToInt(argTwo[client]));
			char nick[64];
			GetClientName(g_client, nick, sizeof(nick));
			
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "Kick", PREFIX, callerName[client], nick); // Получаем перевод и формируем строку
			CPrintToChatAll(txtBufer); // "{1} {2} голосует за исключение игрока {3}"
			createVote(client, GetClientTeam(g_client)); // Вызываем голосование для команды, где находится жертва
		}
		
		// RestartChapter
		if (StrEqual(argOne[client], "RestartChapter", false) || StrEqual(argOne[client], "RestartGame", false))
		{
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "RestartChapter", PREFIX, callerName[client]); // Получаем перевод и формируем строку
			CPrintToChatAll(txtBufer); // "{1} {2} голосует за перезапуск главы!"
			createVote(client, L4D2_TEAM_ALL);
		}
		
		//CPrintToChatAll("Arg1: %s Arg2: %s", argOne[client], argTwo[client]); // Debug
	}
	return Plugin_Handled;
}

public void createVote(int client, int team)
{
	//CPrintToChatAll("createVote: arg1: %s arg2: %s team: %i", argOne[client], argTwo[client], voteInTeam); // Debug
	
	GetClientName(client, callerName[client], sizeof(callerName[])); // Получаем имя игрока
	voteInTeam = team; // В какой тиме будет происходить голосование
	voteName = argOne[client]; // Имя
	votePassAnswer = argTwo[client]; // Ответ
	
	buferArgument = argOne[client]; // Тут хранится аргумент 1
	buferArgument2 = argTwo[client]; // Тут хранится аргумент 2
	
	if (StrEqual(argOne[client], "ChangeAllTalk", false))
	{
		g_AllTalkCvar = FindConVar("sv_alltalk"); // Обращаемся к sv_alltalk
		if (GetConVarInt(g_AllTalkCvar)) // Если Alltalk включен (sv_alltalk 1)
		{
			FormatEx(voteName, sizeof(voteName), "%t", "OffChangeAllTalkVoteName"); // Turn off ALLTalk?
			FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "OffChangeAllTalkVotePass");
		}
		else
		{
			FormatEx(voteName, sizeof(voteName), "%t", "OnChangeAllTalkVoteName"); // Turn on ALLTalk?
			FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "OnChangeAllTalkVotePass");
		}
	}
	if (StrEqual(argOne[client], "KickSpec", false))
	{
		FormatEx(voteName, sizeof(voteName), "%t", "KickSpecVoteName");
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "KickSpecVotePass");
	}
	if (StrEqual(argOne[client], "KillInfectedBots", false))
	{
		FormatEx(voteName, sizeof(voteName), "%t", "KillInfectedBotsVoteName");
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "KillInfectedBotsVotePass");
	}
	if (StrEqual(argOne[client], "ChangeChapter", false))
	{
		FormatEx(txtBufer, sizeof(txtBufer), "%t", argTwo[client]); // Вместо c8m1_apartments получаем = Нет милосердию: 1.Апартаменты
		FormatEx(voteName, sizeof(voteName), "%t", "ChangeChapterVoteName", txtBufer);
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "ChangeChapterVotePass");
	}
	if (StrEqual(argOne[client], "ChangeMission", false))
	{
		FormatEx(txtBufer, sizeof(txtBufer), "%t", argTwo[client]); // Вместо L4D2C8 получаем = Нет милосердию: 1.Апартаменты
		FormatEx(voteName, sizeof(voteName), "%t", "ChangeChapterVoteName", txtBufer);
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "ChangeChapterVotePass");
	}
	if (StrEqual(argOne[client], "Kick", false))
	{
		IntToString(GetClientOfUserId(StringToInt(argTwo[client])), buferArgument2, sizeof(buferArgument2));
		char nick[64];
		GetClientName(GetClientOfUserId(StringToInt(argTwo[client])), nick, sizeof(nick));
		FormatEx(voteName, sizeof(voteName), "%t", "KickVoteName", nick);
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "KickVotePass");
	}
	if (StrEqual(argOne[client], "RestartChapter", false) || StrEqual(argOne[client], "RestartGame", false))
	{
		FormatEx(voteName, sizeof(voteName), "%t", "RestartChapterVoteName");
		FormatEx(votePassAnswer, sizeof(votePassAnswer), "%t", "RestartChapterVotePass");
	}
	
	// Создаем VGUI с голосованием
	BfWrite bf = UserMessageToBfWrite(StartMessageAll("VoteStart", USERMSG_RELIABLE));
	bf.WriteByte(voteInTeam); // Сюда пишем номер команды где отобразится окно с голосованием
	bf.WriteByte(0); // ХЗ что это
	bf.WriteString("#L4D_TargetID_Player"); // Обязательно
	bf.WriteString(voteName); // Текст голосования (Перезапустить кампанию?)
	bf.WriteString(callerName[client]); // Ник игрока
	EndMessage();
	
	// Сбрасываем все флаги
	count_YesVotes = 0;
	count_NoVotes = 0;
	playersCount = 0;
	VoteInProgress = true;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i)) // Могут голосовать только игроки. Не боты
		{
			if (GetClientTeam(i) == voteInTeam) // Голосуют игроки из команды где вызвали голосование
			{
				CanPlayerVote[i] = true;
				playersCount++;
			}
			else if (voteInTeam != 2 && voteInTeam != 3) // Если должны голосовать игроки со всех команд
			{
				CanPlayerVote[i] = true;
				playersCount++;
			}
		}
	}
	
	UpdateVotes();
	delete g_hTimer;
	g_hTimer = CreateTimer(10.0, Timer_VoteCheck); // Спустя это время голосование закончится
}
public Action Timer_VoteCheck(Handle timer) // Таймер
{
	if (VoteInProgress) // Сработал таймер. Если проводится голосование, то...
	{
		//CPrintToChatAll("VoteStop"); // Debug
		VoteInProgress = false; // ...оно завершается
		UpdateVotes();
	}
	return Plugin_Stop;
}

void UpdateVotes()
{
	Event event = CreateEvent("vote_changed");
	event.SetInt("yesVotes", count_YesVotes);
	event.SetInt("noVotes", count_NoVotes);
	event.SetInt("potentialVotes", playersCount); // Количество людей, которые могут голосовать
	event.Fire();
	
	if ((count_YesVotes + count_NoVotes == playersCount) || !VoteInProgress) // Если проголосовали все ИЛИ голосование закончилось, то...
	{
		// Сбрасываем
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				CanPlayerVote[i] = false;
			}
		}
		VoteInProgress = false;
		
		if (count_YesVotes > count_NoVotes) // Если набрали 60% голосов за Путина
		{
			BfWrite bf = UserMessageToBfWrite(StartMessageAll("VotePass"));
			bf.WriteByte(voteInTeam);
			bf.WriteString("#L4D_TargetID_Player");
			bf.WriteString(votePassAnswer);
			EndMessage();
			
			votePassedFunc(); // Здесь находятся функции выполняемые после успешного голосования.
		}
		else // Голосование против
		{
			BfWrite bf = UserMessageToBfWrite(StartMessageAll("VoteFail")); // Выводим "Голосов ЗА должно быть больше"
			bf.WriteByte(voteInTeam);
			EndMessage();
		}
		g_hTimer = null; // https://www.safezone.cc/threads/zaversheno-sourcepawn-sovety-dlja-novichkov-i-profi.37354/#add2
		//CPrintToChatAll("YES: %i NO: %i", count_YesVotes, count_NoVotes); // Debug
	}
}

public void OnMapEnd()
{
	delete g_hTimer;
	delete map_Timer;
}

void votePassedFunc() // Если голосование успешно, то выполняем...
{
	// AllTalk
	if (StrEqual(buferArgument, "ChangeAllTalk", false))
	{
		g_AllTalkCvar = FindConVar("sv_alltalk"); // Обращаемся к sv_alltalk
		
		if (GetConVarInt(g_AllTalkCvar)) // Если Alltalk включен (sv_alltalk 1)
		{
			SetConVarBool(g_AllTalkCvar, false); // Выключаем = sv_alltalk 0
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "AllTalkOFF", PREFIX);
		}
		else
		{
			SetConVarBool(g_AllTalkCvar, true); // = sv_alltalk 1
			FormatEx(txtBufer, sizeof(txtBufer), "%t", "AllTalkON", PREFIX);
		}
		CPrintToChatAll(txtBufer); // "%s Общий чат включен!"
	}
	
	// KickSpec
	if (StrEqual(buferArgument, "KickSpec", false))
	{
		for (int x = 1; x <= MaxClients; x++) // Проходим по всем клиентам сервера
		{
			if (IsValidClient(x) && GetClientTeam(x) == 1) // Если клиент человек и находится в команде наблюдателей, то...
			{
				FormatEx(txtBufer, sizeof(txtBufer), "%t", "KickSpecReason"); // "Вы были исключены голосованием !kickspec" 
				KickClient(x, txtBufer); // Этот текст отобразится у игрока на экране
			}
		}
	}
	
	// KillInfectedBots
	if (StrEqual(buferArgument, "KillInfectedBots", false))
	{
		for (int x = 1; x <= MaxClients; x++)
		{
			if (IsFakeClient(x) && GetClientTeam(x) == 3)
			{
				ForcePlayerSuicide(x);
			}
		}
	}
	
	// ChangeChapter
	if (StrEqual(buferArgument, "ChangeChapter", false))
	{
		FormatEx(mapForChange, sizeof(mapForChange), "%t", buferArgument2);
		delete map_Timer;
		map_Timer = CreateTimer(3.0, Timer_MapChange, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	// ChangeMission
	if (StrEqual(buferArgument, "ChangeMission", false)) // В качестве аргумента приводится L4D2C8 вместо c8m1_apartments
	{
		char buf[sizeof(buferArgument2)];
		FormatEx(buf, sizeof(buf), "map%s", buferArgument2); // Добавляем к L4D2C1 слово map = mapL4D2C1
		FormatEx(mapForChange, sizeof(mapForChange), "%t", buf); // Даём L4D2C1, получаем c1m1_hotel
		delete map_Timer;
		map_Timer = CreateTimer(3.0, Timer_MapChange, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	// Kick
	if (StrEqual(buferArgument, "Kick", false))
	{
		FormatEx(txtBufer, sizeof(txtBufer), "%t", "KickReason"); // "Вы были исключены голосованием " 
		KickClient(StringToInt(buferArgument2), txtBufer); // Этот текст отобразится у игрока на экране
	}
	
	// RestartChapter
	if (StrEqual(buferArgument, "RestartChapter", false) || StrEqual(buferArgument, "RestartGame", false))
	{
		GetCurrentMap(mapForChange, sizeof(mapForChange)); // Получаем называние карты (c8m1_apartments)
		delete map_Timer;
		map_Timer = CreateTimer(3.0, Timer_MapChange, _, TIMER_FLAG_NO_MAPCHANGE); // Меняем на ту же самую карту
	}
}

public Action Timer_MapChange(Handle timer) // Таймер
{
	map_Timer = null; // Убиваем таймер
	L4D2_ChangeLevel(mapForChange); // При помощи native void L4D2_ChangeLevel меняем карту.
	return Plugin_Stop;
}

public Action vote(int client, int args)
{
	if (VoteInProgress && CanPlayerVote[client] == true)
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof arg); // Получаем аргумент Yes или No
		
		//PrintToServer("Got vote %s from %i", arg, client); // Debug
		
		if (strcmp(arg, "Yes", true) == 0) // Если игрок нажал F1 (Vote Yes)
		{
			count_YesVotes++;
		}
		else if (strcmp(arg, "No", true) == 0) // Если игрок нажал F2 (Vote No)
		{
			count_NoVotes++;
		}
		CanPlayerVote[client] = false; // Запрещаем голосовать повторно
		UpdateVotes();
	}
	return Plugin_Stop;
}

stock bool IsValidClient(int client) {
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

public Action voteYes(client, args)
{
	for (new i = 1; i <= MaxClients; i++) // Заставляем всех клиентов...
	{
		if (IsValidClient(i))
		{
			FakeClientCommandEx(i, "Vote Yes"); // ...голосовать ЗА
		}
	}
	return Plugin_Handled;
	//PrintToServer("[NEWVOTESYSTEM] Voted YES"); // Debug
}
public Action voteNo(client, args)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			FakeClientCommandEx(i, "Vote No");
		}
	}
	return Plugin_Handled;
	//PrintToServer("[NEWVOTESYSTEM] Voted NO"); // Debug
} 