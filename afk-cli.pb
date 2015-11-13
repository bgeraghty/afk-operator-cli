IncludeFile "irc_special_chars.pbi" 
IncludeFile "WinHTTP.pbi"

Global DatabaseFileName$ = "afk.db"

Global IRC_Bot_Version$ = "0."+Str(#PB_Editor_BuildCount)+"."+Str(#PB_Editor_CompileCount) + " Beta"

Enumeration
  #AFK_PRIVMSG_PRIVATE ; Used to tag a message that was sent to the bot privately
  #AFK_PRIVMSG_CHANNEL ; Used to tag a message that was sent to a public #Channel
EndEnumeration

Global Socket_Buffer_Size.i = 16384 ; The amount of bytes that can be read at one time on the network
Global Connected = 0 ; Boolean-esque variable that tells us if we are still connected.  It is tested for periodically
Global IRCSocket ; Handle of the main Socket to communicate over IRC
Global CR$ = Chr(13)+Chr(10) ; Shorthand for Carriage-Return
Global IRC_Server$ = "irc.cyberghetto.net" ; The Sever/Network address we will connect to
Global IRC_Host$ = "" ; This variable will store the name of the server/host you connect to on the IRC Network
Global IRC_Port = 6667 ; TCP/IP Connection Port
Global BotNick$ = "afkBot" ; My NickName in IRC
Global BotUser$ = "afkBot" ; UserName, used for Logging In
Global BotHost$ = ""
Global BotIDFull$ = ""
Global NickServPass$ = "my_password"  ; The password this bot is going to give to NickServ if it needs to login to the server.
Global Bot_Away_Status.i = #False ; This holds a value to find out if you are currently set to AWAY on the server.
Global SentBytes.i = 0 ; Total count of bytes sent using Sockets
Global RecvBytes.i = 0 ; Total count of bytes received using Sockets
Global RecvLines.i = 0 ; Total count of lines received from anywhere
Global SentLines.i = 0 ; Total count of lines sent to server
Global Console_Busy= #False ; Boolean variable to ensure that threads take turns writing to the console
Global CommandIDChar$ = "!" ; Character that designates a PRIVMSG is a Bot-Command
Global UI_Focused_Channel$ = "" ; A channel variable, when filled, will direct all I/O to a single channel.
Global UI_Show_Title_Status.i = #True ; Creates a thread which constantly updates the titlebar info
Global UI_TotalWidth = 150 ; Default Width of 150
Global UI_TotalHeight= 75 ; Default Height of 75
Global UI_LinesInBuffer.i = 0 ; Keeps track of how many text lines have been printed to the console.
Global TotalChannelsAvailable.i

Global UI_Cursor_Position.COORD

Macro ConsoleHandle() ; Macro returns the console's handle..
  GetStdHandle_( #STD_OUTPUT_HANDLE ) 
EndMacro
  
Macro MAKEWORD(a, b) ; Macro to generate Winsock Version Information
  (a & $FF)|((b & $FF)<<8)
EndMacro

Structure tConsole_COORD
   StructureUnion
      coord.COORD
      long.l
   EndStructureUnion
EndStructure

Structure IRC_Channel ; Properties of an IRC Channel
  ChannelName$ ; The #Name of the channel
  ChannelModes$ ; The Channel Modes 
  MyChanModes$ ; Modes set on the bot, in the channel (+v, +o, etc)
  IsChannelOperator.i ; Boolean for do i have +o
  ChannelTopic$ ; The Topic String, collected from a [332] line
  ChannelTopicDate$ ; Topic Date, collected from Line [333]
  ChannelTopicAuthor$ ; the Nick of the person to last set the topic.  Also in Line [333]
  List Users.s() ; A list of the Nicks int the channel, compiled from [353] Lines provided by server.
EndStructure

Structure Available_Channel ; Used to store channels returned from a LIST command, as well as a topic/description line
  ChannelName$ ; Name of registered channel
  Description$ ; Description / Topic
EndStructure

Structure Bot_Operator ; Properties of a bot-admin, or operator: ***** (Not Yet Implemented In This Version) *****
  OperNick$ ; The Admin's Nickname
  OperHost$ ; The Admin's hostname, used for validation and login
  OperPass$ ; The Admin's password, so the bot will recognize you
  LoggedIn.i ; Whether the Admin/Oper is currently signed in (Boolean)
  Enabled.i ; Whether this Admin account is enabled, and will allow logins. (Also Bool)
  FailedLogins.i ; Never Implemented. Future space to statistically count bad login attempts
EndStructure

Structure PlugCommand ; Properties of a command-plugin: ***** (Not Yet Implemented In This Version) *****
  LibPath$ ; Where the DLL is
  CMDString$ ; What the command-name is
  FuncAddr.l ; Memory Address within the DLL where command can be triggered
  DisabledChans$ ; Channels which this command will not work / blocked / ignored
  OperOnly.i ; Whether the command can only be launched by a registered, logged-in admin
  Enabled.i ; Whethere the command is activated, for anyone, anywhere
EndStructure

Structure BackLogLine
  EntireLineString$
  TimeStamp.i
EndStructure

Global NewList Master_Recipients.s() ; A list of all possible Nicks/Channels you can send messages to
Global NewList Rec_Sent.s() ; A list of previous lines of console input
Global NewList UI_AvailableCommands.s() ; A manually-populated List of the console commands for tab-complete
Global NewList AutoJoinListItem.s() ; List of Channels which can be automatically joined in sequence.  This is an auto-start feature, more to come soon.
Global NewList ReadLines.s() ; List used to store + queue IRC Lines to be processed when they are arriving faster than can be processed.
Global NewList BackLogLines.BackLogLine() ; List which stores received lines for re-analysis or console output.
Global NewList AvailableChannels.Available_Channel() ; Stores a list of channels sent after a LIST command is issued.

Global NewList OperListItem.Bot_Operator() ; List of Users allowed to administer the bot. ***** (Not Yet Implemented In This Version) *****

Global NewList ChannelsJoined.IRC_Channel() ; List of IRC_Channel Structs.  List automatically Grows and populates when you join #channels, and shrinks when you /part them

Global NewList PluginFuncs.PlugCommand() ; List of PluginCommand Structures.  This managed list is essentially which plugins are currently loaded ***** (Not Yet Implemented In This Version) *****

Declare IRC_ScanLine(TheSocket, EntireLine$, TimeDate.i, PrintOnly=#False) ; Pre-Declaration

Declare.i IRC_InChannel(TheChannel$) ; Pre-Declaration

Declare.s IRC_GetChannel(Line$) ; Pre-Declaration

Declare.i IRC_FindMasterRecipients(Recipient$) ; Pre-Declaration

Procedure UI_GetCursorXY(*ptr.COORD) ; Get current X/Y of the cursor. The @my.COORD variable passed to this will be updated.
  Protected CSBI.CONSOLE_SCREEN_BUFFER_INFO
  GetConsoleScreenBufferInfo_(GetStdHandle_(#STD_OUTPUT_HANDLE), @CSBI)
  *ptr\x = CSBI\dwCursorPosition\x
  *ptr\y = CSBI\dwCursorPosition\y
EndProcedure

Procedure UI_ConsoleWidth() ; Get Current Characther Width of Console Window
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   
   ProcedureReturn ConsoleBufferInfo\srWindow\right - ConsoleBufferInfo\srWindow\left + 1
EndProcedure

Procedure UI_ConsoleHeight() ; Get Current Characther Height of Console Window
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   
   ProcedureReturn ConsoleBufferInfo\srWindow\bottom - ConsoleBufferInfo\srWindow\top + 1
EndProcedure

Procedure UI_ConsoleBufferWidth() ; Get Console Buffer W.
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   
   ProcedureReturn ConsoleBufferInfo\dwSize\x
EndProcedure

Procedure UI_ConsoleBufferHeight() ; Get Console Buffer H.
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   
   ProcedureReturn ConsoleBufferInfo\dwSize\y
EndProcedure

Procedure UI_ConsoleMoveUp( CountLines = 1 ) ; Move Curser Up X amount of lines
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole, x, y
   Protected location.tConsole_COORD
   
   If CountLines < 1 : ProcedureReturn #False : EndIf
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   location\coord = ConsoleBufferInfo\dwCursorPosition
   location\coord\x = 0
   location\coord\y - CountLines
   If location\coord\y < 0 : location\coord\y = 0
   ElseIf location\coord\y >= ConsoleBufferInfo\dwSize\y : location\coord\y = ConsoleBufferInfo\dwSize\y - 1 : EndIf
   SetConsoleCursorPosition_( hConsole, location\long )
   
   ProcedureReturn #True
EndProcedure

Procedure UI_ConsoleDeletePrevLines( CountLines = 1 ) ; Delete Previous Lines
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole, x, y
   Protected location.tConsole_COORD
   
   If CountLines < 1 : ProcedureReturn #False : EndIf
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   location\coord\x = 0
   location\coord\y = ConsoleBufferInfo\dwCursorPosition\y
   While CountLines And location\coord\y
      location\coord\y - 1
      SetConsoleCursorPosition_( hConsole, location\long )
      Print( Space(ConsoleBufferInfo\dwSize\x) )
      If CountLines = 1
         SetConsoleCursorPosition_( hConsole, location\long )
      EndIf
      CountLines - 1
   Wend
   
   ProcedureReturn #True
EndProcedure

Procedure UI_ConsoleBufferLocate( x, y ) ; Relocate Cursor to specific X Y position
   Protected ConsoleBufferInfo.CONSOLE_SCREEN_BUFFER_INFO
   Protected hConsole
   Protected location.tConsole_COORD
   
   If y < 0 Or y < 0
      ; x or y outside the console screen buffer
      ProcedureReturn #False
   EndIf
   
   hConsole = ConsoleHandle()
   GetConsoleScreenBufferInfo_( hConsole, @ConsoleBufferInfo )
   
   If y >= ConsoleBufferInfo\dwSize\y Or x >= ConsoleBufferInfo\dwSize\x
      ; x or y outside the console screen buffer
      ProcedureReturn #False
   EndIf
   
   location\coord\x = x
   location\coord\y = y
   SetConsoleCursorPosition_( hConsole, location\long )
   
   ProcedureReturn #True
EndProcedure

Procedure.s UI_GetConsoleTitle() ; Return the current title of the console screen
   Protected title.s = Space(1024)
   GetConsoleTitle_( @title, 1024 )
   ProcedureReturn title
 EndProcedure
 
Procedure UI_SetConsoleBufferSize(handle.i, characterWidth.i, characterHeight.i) ; Changes the vertical and horizontal size of a console (cmd) window.
  Protected consoleInfo.CONSOLE_SCREEN_BUFFER_INFO
  Protected rect.SMALL_RECT
  GetConsoleScreenBufferInfo_(handle, @consoleInfo) 
  If characterWidth < consoleInfo\dwSize\x Or characterHeight < consoleInfo\dwSize\y 
    If characterWidth < 13 ;Smaller thant 13 seems not possible
      rect\right = 13 - 1 
      characterWidth = 13 
    ElseIf characterWidth < consoleInfo\dwSize\x 
      rect\right = characterWidth - 1 
    Else 
      rect\right = consoleInfo\dwSize\x - 1 
    EndIf 
    If characterHeight <= 0 
      rect\bottom = 1 - 1 
      characterHeight = 1 
    ElseIf characterHeight < consoleInfo\dwSize\y 
      rect\bottom = characterHeight - 1 
    Else 
      rect\bottom = consoleInfo\dwSize\y - 1 
    EndIf
    SetConsoleWindowInfo_(handle, 1, @rect) 
  EndIf 
  SetConsoleScreenBufferSize_(handle, characterWidth + (65536 * characterHeight)) 
EndProcedure 

Procedure UI_ReDraw(TheSocket) ; Re-Draw the screen based on filters, etc.
  Protected NewList Temp_List.s()
  ClearList(Temp_List())
  UI_ConsoleDeletePrevLines(UI_TotalHeight)
  UI_ConsoleBufferLocate(0, 0)
  UI_LinesInBuffer = 0
  While UI_LinesInBuffer < UI_TotalHeight-1
    If UI_Focused_Channel$ <> ""
      PrintN("                         | ")
    Else
      PrintN("                                 | ")
    EndIf
    UI_LinesInBuffer = UI_LinesInBuffer + 1
    ;Delay(1)
  Wend
  ForEach BackLogLines()
    IRC_ScanLine(TheSocket, BackLogLines()\EntireLineString$, BackLogLines()\TimeStamp, #True)
  Next
EndProcedure

Procedure.s StringBetween(SourceString$, String1$, String2$, OccurenceNumber.i=0, StartPos.i=0) ; An old function to find and pull strings out of larger strings. Yep.
  Protected Start1.i = StartPos
  Protected End1.i = 0
  Protected I.i = 0
  If OccurenceNumber <> 0
    For I = 0 To OccurenceNumber
      Select I
        Case 0
          Start1 = FindString(SourceString$, String1$, Start1) + Len(String1$)
        Default
          Start1 = FindString(SourceString$, String1$, Start1) + Len(String1$)
      EndSelect
    Next
  Else
    Start1 = FindString(SourceString$, String1$, 0) + Len(String1$)
  EndIf
  End1 = FindString(SourceString$, String2$, Start1)
  End1 - Start1
  If End1 = 0 : End1 = Len(SourceString$) : EndIf
  ProcedureReturn Mid(SourceString$, Start1, End1)
EndProcedure

Procedure.i InitializeSockets() ; Initialize Winsock for networking use in the program.
  wsaData.WSADATA
  wVersionRequested.w = MAKEWORD(2,2)
  iResult = WSAStartup_(wVersionRequested, @wsaData)
  If iResult <> #NO_ERROR
    Debug "Error at WSAStartup()"
    ProcedureReturn #False
  Else
    Debug "WSAStartup() OK."
    ProcedureReturn #True
  EndIf
EndProcedure

Procedure.i ShutdownSockets(ShowError.i=0) ; If there is an error, or we simply want to quit, this will close+free the sockets
  If ShowError <> 0
    PrintN("Error: " + Str(WSAGetLastError_()))
  EndIf
  WSACleanup_()
  Debug "WSACleanup() OK."
EndProcedure

Procedure.s HostnameToIP(HostName.s) ; Winsock, returns an IP Address based on a hostname, [needs error handling for zero-length input]
  If Len(HostName) > 0 
    ResultIP.s=""    
    *host.HOSTENT = gethostbyname_(HostName)
    If *host <> #Null
      IPAddr.l = PeekL(*host\h_addr_list)
      ResultIP = StrU(PeekB(IPAddr),#PB_Byte)+"."+StrU(PeekB(IPAddr+1),#PB_Byte)+"."+StrU(PeekB(IPAddr+2),#PB_Byte)+"."+StrU(PeekB(IPAddr+3),#PB_Byte)
    EndIf 
    ProcedureReturn ResultIP 
  EndIf 
EndProcedure

Procedure.s Get_Local_FQDN() ; Allows the bot to determine its own Fully-Qualified Domain Name
  Protected BufferSize.I
  If GetNetworkParams_(0, @BufferSize) = #ERROR_BUFFER_OVERFLOW
    Protected *Buffer = AllocateMemory(BufferSize)
    If *Buffer
      Protected Result = GetNetworkParams_(*Buffer, @BufferSize)
      If Result = #ERROR_SUCCESS
        Hostname$ = PeekS(*Buffer)
        DomainName$ = PeekS(*Buffer + 132)
        FQDN$ = PeekS(*Buffer) + "." + PeekS(*Buffer+132)
      EndIf
      FreeMemory(*Buffer)
    EndIf
  EndIf
  ProcedureReturn FQDN$
EndProcedure

Procedure.i Create_Socket_Connect(ServerHostName$, Port.i) ; Creates a new socket, and if all goes well, connects to your server, returning a Socket Handle
  ResultSocket = SOCKET_(#AF_INET, #SOCK_STREAM, #IPPROTO_TCP)
  If ResultSocket = #INVALID_SOCKET
    Debug "Error at Socket(): " + Str(WSAGetLastError_())
    ShutdownSockets(1)
    ProcedureReturn #INVALID_SOCKET
  EndIf
  *ptr = client.sockaddr_in
  client\sin_family = #AF_INET
  client\sin_addr = inet_addr_(HostnameToIP(ServerHostname$))
  client\sin_port = htons_(Port)
  If connect_(ResultSocket, *ptr, SizeOf(sockaddr_in)) = #SOCKET_ERROR
    ShutdownSockets(1)
    ProcedureReturn #INVALID_SOCKET
  Else
    Connected = 1
    Debug "Socket Created: " + Str(ResultSocket)
    ProcedureReturn ResultSocket
  EndIf
EndProcedure  

Procedure IRC_ConsolePrintLine(TheSocket, Line_From$, Line_Sent_To$, Line_Text$, Line_TheChannel$,    ; Console Output.
                               Line_ID_Code$, Line_From_UserHost$, Line_From_UserName$, Line_From_FullStr$,
                               Line_My_Chan_Modes$,Line_Param_6$,Line_Param_5$,Line_Param_4$,Line_TimeStamp.i,
                               Line_Type.i, Line_Respond_To$, Bot_Nickname$)
  

  ;[MAIN VARIABLES]=======================================================================================;
  Protected Max_Len.i = UI_TotalWidth - 38 ; ...................................... Maximum space available for Line_Text.;
  Protected fLen = 8       ; ....................................................Max Length for From User.;
  Protected Indent$ = "                               | "
  L_Text_Color.i = 8
  L_Text_Bkg.i = 0
  From_Color.i = 3
  To_Color.i = 2
  ;[VERIFY DISPLAY FILTER]================================================================================;
  If UI_Focused_Channel$ <> "" And ( IRC_InChannel(UI_Focused_Channel$) Or IRC_FindMasterRecipients(UI_Focused_Channel$) )
    fLen = fLen + 8
    Indent$ = "                         | "
    If Left(UI_Focused_Channel$, 1) = "#"
      Debug "Channel Filtering"
      If Line_TheChannel$ <> UI_Focused_Channel$
        ProcedureReturn
      EndIf
    Else
      Debug "User Filtering"
      Debug "UI_FIlter: " + UI_Focused_Channel$
      Debug "Sent To: " + Line_Sent_To$
      Debug "From : " + Line_From$
      If (Line_Sent_To$ <> UI_Focused_Channel$ ) And (Line_From$ <> UI_Focused_Channel$)
        ProcedureReturn
      EndIf
    EndIf 
  EndIf
  
  UI_LinesInBuffer = UI_LinesInBuffer + 1 ; We now know this line IS getting printed.
  
  Select Line_ID_Code$
    Case "301"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
      L_Text_Color = 7
    Case "307"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
      L_Text_Color = 7
    Case "319"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
      L_Text_Color = 7
    Case "313"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
       L_Text_Color = 7
    Case "310"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
       L_Text_Color = 7
    Case "671"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
      L_Text_Color = 7
    Case "321"
      Line_Text$ = "Channels List:"
      Line_Sent_To$ = "**LIST**"
      L_Text_Color = 11
    Case "322"
      Line_Text$ = "["+Line_Param_4$+"] ("+Line_Param_5$+" Users) - " + Line_Text$
      Line_Sent_To$ = "**LIST**"
      L_Text_Color = 3
    Case "323"
      ;TotalChannelsAvailable = ListSize(AvailableChannels())
      Line_Text$ = Str(TotalChannelsAvailable) + " channels."
      Line_Sent_To$ = "**LIST**"
      L_Text_Color = 11
    Case "332"
      Line_Text$ = "Topic for "+Line_TheChannel$+" is '"+Line_Text$+"'."
      L_Text_Color = 10
    Case "333"
      Line_Text$ = "Set by " + Line_Param_5$ + ". " +FormatDate("(%yyyy/%mm/%dd - %hh:%mm:%ss)", Val(Line_Param_6$))
      L_Text_Color = 8
    Case "353", "366", "376", "318"
      ProcedureReturn
    Case "311"
      Line_Text$ = Line_Param_4$ + " = ("+Line_Param_5$+"@"+Line_Param_6$+"), AKA: '"+ Line_Text$+"'"
      L_Text_Color = 7
    Case "312"
      Line_Text$ = Line_Param_4$ + " is connected to " + Line_Param_5$ + " ("+Line_Text$+")"
      L_Text_Color = 7
    Case "317"
      Line_Text$ = Line_Param_4$ + " has been idle for: "+ Line_Param_5$ + " seconds, and has been signed on since " + FormatDate("%yyyy/%mm/%dd - %hh:%mm:%ss", Val(Line_Param_6$))
      L_Text_Color = 7
    Case "378"
      Line_Text$ = Line_Param_4$ + " " + Line_Text$
      L_Text_Color = 7
    Case "JOIN"
      If Line_From$ = BotNick$
        Line_Text$ = "You have successfully joined "+Line_TheChannel$+"."
      Else
        Line_Text$ = Line_From$+" has joined "+Line_TheChannel$+"."
      EndIf 
      L_Text_Color = 10
    Case "PART"
      L_Text_Color = 4
      If Line_From$ = BotNick$
        Line_Text$ = "You have successfully parted (left) "+Line_Sent_To$+"."
      Else
        Line_Text$ = Line_From$ + " has parted (left) "+Line_Sent_To$+"."
      EndIf 
    Case "NOTICE"
      Line_Text$ = Line_Text$
      Line_Sent_To$ = "*NOTICE*"
      To_Color = 6
      L_Text_Color = 6
    Case "MODE"
      Line_Text$ = Line_From$ + " Sets MODE "+ Line_Text$ + ": " + Line_Sent_To$
      L_Text_Color = 5
    Default 
      ;
  EndSelect
  If FindString(Line_Sent_To$, "#")
        To_Color = 10
      EndIf
  Line_Text$ = RemoveString(Line_Text$, #IRC_ULINE_TEXT)
  Line_Text$ = RemoveString(Line_Text$, #IRC_BOLD_TEXT)
  ;Debug "Print: " + Str(UI_LinesInBuffer)
  ;[FORMAT LINES FOR CONSOLE OUTPUT]======================================================================;
  While Console_Busy ; ........ loop ensures more than 1 thread isn't writing to console at the same time.;
    Delay(1) ; ........................................................................5ms between checks.;
  Wend ; .................................................................................................;
  Console_Busy = #True ; ................................................................Time to get busy.;
  ;=======================================================================================================; 
  Line_Sent_To$ = LTrim(ReplaceString(Line_Sent_To$, ":", "")); ..........................................;
  Protected Output_From$ ; ................. Temporary variable to store formatted output for the console.;
  If Len(Line_From$) > fLen ; .................................. If the Nick is longer than 8 characters.;
    Output_From$ = Left(Line_From$, (fLen-2))+".." ; ................ Copy the first 6, and end with periods.;
  Else ; ............................................If the Nick is shorter than or equal to 6 characters.;
    Output_From$ = Line_From$ ; ................................... Copy it to the temporary variable.;
    While Len(Output_From$) <= (fLen-1) ; ................................If the Nick is less or eq 7 characters.;
      Output_From$ = "." + Output_From$ ; ...... Add blank space to Nick until it is exactly 7 characters.;
    Wend ; ...............................................................................................;
  EndIf ; ................................................................................................;
  ;=======================================================================================================;
  Protected Output_To$ ; ...... Same as above, except this time we are formating who the line was sent to.;
  If Len(Line_Sent_To$) > 8 ; ................................... If the nick is longer than 8 characters.;
    Output_To$ = Left(Line_Sent_To$, 6)+".." ; ............................ shorten it to fit the profile.;
  Else ; ................................................................Nick was already <= 8 characters.;
    Output_To$ = Line_Sent_To$ ; ...................................... Copy variable so it can be edited.;
    While Len(Output_To$) <= 7 ; ......................................If Nick is less than 7 Characters..;
      Output_To$ = "." + Output_To$ ; ..............................Again, Add blank space to fit 8-chars.;
    Wend ; ...............................................................................................;
  EndIf ; ................................................................................................;
  ;=======================================================================================================;
  Protected Output_ID$ = Line_ID_Code$ + ":"; ................... Now we format the standard length of ID.;
  If Len(Output_ID$) > 6 : Output_ID$ = Left(Output_ID$, 5)+":" : EndIf ; ................................;
  While Len(Output_ID$) <= 5  ; ..........................................................................;
      Output_ID$ = Output_ID$ + " " ; ...................................... Add Blank Space if necessary.;
  Wend                            ; .................................................................................................;  
  If UI_Focused_Channel$ <> "" And IRC_InChannel(UI_Focused_Channel$) 
    UI_ConsoleBufferLocate(0, UI_LinesInBuffer-1)
  Else
    UI_ConsoleBufferLocate(0, UI_LinesInBuffer-1)
  EndIf
  ConsoleColor(7,0) : Print(FormatDate("%hh:%ii ", Line_TimeStamp )); .............Timestamp (Uses White).; 
  ConsoleColor(From_Color,0) : Print("<"+Output_From$+"> ") ; .................. Displays who sent the Line (Cyan).;
  ;.............................Action / ID (Yellow/Tan).;
  If UI_Focused_Channel$ = ""
    ConsoleColor(15,0) : Print("-> ");Print("" + Output_ID$ + "")  ; 
    ConsoleColor(To_Color,0) : Print("<" + Output_To$+"> ")
  Else
    ;
  EndIf
  ConsoleColor(8,0) : Print("| ") : ConsoleColor(L_Text_Color,L_Text_Bkg)
  If Len(Line_Text$) > Max_Len
    Print(Left(Line_Text$, Max_Len)) : PrintN("")
    Line_Text$ = Right(Line_Text$, Len(Line_Text$)-Max_Len)
    While Len(Line_Text$) > Max_Len
      ConsoleColor(8,0) : Print(Indent$)
      ConsoleColor(L_Text_Color, 0) : Print(Left(Line_Text$, Max_Len)) : PrintN("")
      Line_Text$ = Right(Line_Text$, Len(Line_Text$)-Max_Len)
    Wend
    ConsoleColor(8,0) : Print(Indent$) : ConsoleColor(L_Text_Color, 0) : Print(Line_Text$) : PrintN("")
  Else
    Print(Line_Text$) : PrintN("")
  EndIf
  UI_ConsoleBufferLocate(0, UI_TotalHeight-1)
  ConsoleColor(8,0)
  Console_Busy = #False ; .free up this procedure in case something else is waiting to use it (and it is).;
  ;====================================================================[/FORMAT LINES FOR CONSOLE OUTPUT]=/ 
EndProcedure

Procedure.i IRC_RawText(TheSocket, TheText$) ; Sends Raw Text to the Server.  All sent lines pass through here.
  Debug "Send: " + TheText$
  If TheSocket <> #SOCKET_ERROR And Len(TheText$) > 0
    If Not FindString(TheText$, CR$) : TheText$ = TheText$ + CR$ : EndIf  
    ResultBytes.i = send_(TheSocket, @TheText$, Len(TheText$), 0)
    If ResultBytes > 0
      SentLines = SentLines + 1 ; Statistics
      SentBytes = SentBytes + ResultBytes
      ProcedureReturn #True
    Else
      ProcedureReturn #False
    EndIf 
  EndIf
EndProcedure

Procedure.i IRC_SendText(TheSocket, SendTo$, TheText$) ; Send a PRIVMSG to a specific name, over a specific Socket
  IRC_RawText(TheSocket, "PRIVMSG " + SendTo$ + " :" + TheText$)
  IRC_ScanLine(TheSocket, ":"+BotIDFull$+" PRIVMSG "+SendTo$+" :"+TheText$, Date())
  AddElement(BackLogLines())
  BackLogLines()\EntireLineString$ = ":"+BotIDFull$+" PRIVMSG "+SendTo$+" :"+TheText$
  BackLogLines()\TimeStamp = Date()
EndProcedure

Procedure.s IRC_GetFrom(Line$) ; Returns the Nick of the Sender of the Line
  If StringBetween(Line$, ":", "!") <> "" And Not FindString((StringBetween(Line$, ":", "!")), " ")
    ProcedureReturn StringBetween(Line$, ":", "!")
  Else
    ProcedureReturn StringBetween(Line$, ":", " ")
  EndIf
EndProcedure

Procedure.s IRC_GetFullFrom(Line$) ; Returns the ID of the Sender, Formatted as Nick!User@Host.tld
  ProcedureReturn Trim(StringField(Line$, 1, " "),":")
EndProcedure

Procedure.s IRC_GetCode(Line$) ; Returns the IRC/2 Line Identifier Code/String
  ProcedureReturn StringField(Line$, 2, " ")
EndProcedure

Procedure.s IRC_GetTo(Line$) ; Returns the Nick which a specific Line was sent to
  ProcedureReturn StringField(Line$, 3, " ")
EndProcedure

Procedure.s IRC_GetP4(Line$) ; Returns the letters representing the change taking place as a result of a MODE command (Param 4)
  ProcedureReturn StringField(Line$, 4, " ")
EndProcedure

Procedure.s IRC_GetP5(Line$) ; Returns the target Nickname of a Server MODE command (Param 5 If applicable)
  ProcedureReturn StringField(Line$, 5, " ")
EndProcedure

Procedure.s IRC_GetP6(Line$) ; Returns the 6th Param (IF applicable)
  ProcedureReturn StringField(Line$, 6, " ")
EndProcedure

Procedure.s IRC_GetText(Line$) ; Separate and return only the Text / Message / Params part of a line
  Protected Start = FindString(Line$, ":", FindString(Line$, "PRIVMSG", 2)+Len("PRIVMSG"))
  If Start = 0
    Start = FindString(Line$, IRC_GetTo(Line$) + " ", FindString(Line$, "PRIVMSG", 2)+Len("PRIVMSG")) + Len(IRC_GetTo(Line$)) 
  EndIf
  ProcedureReturn Right(Line$, Len(Line$)-Start)
EndProcedure

Procedure.s IRC_GetFromUsername(Line$) ; Find the UserName of the person that sent the line
  ProcedureReturn StringBetween(IRC_GetFullFrom(Line$), "!", "@")
EndProcedure

Procedure.s IRC_GetFromHost(Line$) ; Find the Hostname of the person that sent the line
  ProcedureReturn StringBetween(IRC_GetFullFrom(Line$)+" ", "@", " ")
EndProcedure

Procedure.s IRC_GetChannel(Line$) ; Finds and returns the associated '#Channel' name in most IRC Lines
  Protected Total.i = CountString(Line$, " ")
  Protected I.i = 0
  Protected Temp$ = ""
  Select IRC_GetCode(Line$)
    Case "372"
      ProcedureReturn
    Case "JOIN"
      If Not FindString(IRC_GetText(Line$), " ") And IRC_GetText(Line$) <> ""
        ProcedureReturn IRC_GetText(Line$)
      Else
        ProcedureReturn IRC_GetTo(Line$)
      EndIf
    Case "PART"
      If Not FindString(IRC_GetText(Line$), " ") And IRC_GetText(Line$) <> ""
        ProcedureReturn StringField(Line$, 3, " ")
      Else
        ProcedureReturn IRC_GetTo(Line$)
      EndIf 
    Default
      For I = 1 To Total
        Temp$ = StringField(Line$, I, " ")
        If Left(Temp$, 1) = "#"
          If Not FindString(Trim(Temp$ , ":"), " ")
            ProcedureReturn Trim(Temp$, ":")
          Else
            ProcedureReturn "#" + StringBetween(Line$, "#", " ")
          EndIf 
        EndIf
      Next
  EndSelect
EndProcedure

Procedure IRC_UpdateUsersInChan(Channel$, UserList$) ; Function designed to have [353] text lines thrown at it, and sort/add/remove/replace the users in your userlists
  UserList$ = Trim(UserList$) + " "
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = Channel$
      If Trim(UserList$) <> ""
        Protected NameCountCurrent.i = CountString(UserList$, " ")
        For X = 1 To NameCountCurrent
          AddElement(ChannelsJoined()\Users())
          ChannelsJoined()\Users() = StringField(UserList$, X, " ")
          AddElement(Master_Recipients())
          Master_Recipients() = StringField(UserList$, X, " ")
        Next
        SortList(ChannelsJoined()\Users(), #PB_Sort_Ascending | #PB_Sort_NoCase)
        Protected Current$ = "@@@@@"
        ForEach ChannelsJoined()\Users()
          If ChannelsJoined()\Users() <> Current$
            Current$ = ChannelsJoined()\Users()
          Else
            DeleteElement(ChannelsJoined()\Users())
          EndIf
        Next
        SortList(Master_Recipients(), #PB_Sort_Ascending | #PB_Sort_NoCase)
        Current$ = "@@@@@"
        ForEach Master_Recipients()
          If Master_Recipients() <> Current$
            Current$ = Master_Recipients()
          Else
            DeleteElement(Master_Recipients())
          EndIf
        Next
      EndIf
    EndIf
  Next
EndProcedure

Procedure.i IRC_UpdateChanList(TheChannel$) ; Add a new channel to the lists, after joining.  If already joined.. #False
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      ProcedureReturn #False
    EndIf
  Next
  AddElement(ChannelsJoined())
  ChannelsJoined()\ChannelName$ = TheChannel$
  ProcedureReturn #True
EndProcedure

Procedure.i IRC_UpdateChanMasterRecipients(TheChannel$) ; Add Users/Channels to master Recip. List
  ForEach Master_Recipients()
    If Master_Recipients() = TheChannel$
      ProcedureReturn #False
    EndIf
  Next
  AddElement(Master_Recipients())
  Master_Recipients() = TheChannel$
  ProcedureReturn #True
EndProcedure

Procedure.i IRC_RemoveChanMasterRecipients(TheChannel$) ; Remove Users/Channels from master Recip. List.  Remove channel when parting it (self)
  ForEach Master_Recipients()
    If Master_Recipients() = TheChannel$
      DeleteElement(Master_Recipients())
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False  
EndProcedure

Procedure.i IRC_FindMasterRecipients(Recipient$) ; Check for presence of a User/Channel
  ForEach Master_Recipients()
    If Recipient$ = Master_Recipients()
      ProcedureReturn #True
    EndIf  
  Next
  ProcedureReturn #False  
EndProcedure

Procedure.i IRC_RemoveChanList(TheChannel$) ; Remove an entire Channel from local lists, along with all sub-data.
  Protected Result.i = #False
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      DeleteElement(ChannelsJoined())
      Result = #True
    EndIf
  Next
  ProcedureReturn Result
EndProcedure

Procedure.i IRC_InChannel(TheChannel$) ; Boolean verification that we are currently in the given Channel.
  Protected Result.i = #False
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      Result = #True
    EndIf 
  Next
  ProcedureReturn(Result)
EndProcedure

Procedure.i IRC_UpdateMyChanModes(TheChannel$, MyModes$) ; Add or remove the modes specified by the Server Line
  Protected AddModes.i
  Debug "Provided MYMODES: " + MyModes$
  If FindString(MyModes$, "+")
    AddModes = #True
    MyModes$ = RemoveString(MyModes$, "+")
    Debug "Adding MYMODES: " + MyModes$
  Else
    AddModes = #False
    MyModes$ = RemoveString(MyModes$, "-")
    Debug "Removing MYMODES: " + MyModes$
  EndIf
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      Select AddModes
        Case #True
          For I = 1 To Len(MyModes$)
            If Not FindString(ChannelsJoined()\MyChanModes$, Left(MyModes$,I))
              ChannelsJoined()\MyChanModes$ = ChannelsJoined()\MyChanModes$ + Left(MyModes$, I)
              MyModes$ = RemoveString(MyModes$, Left(MyModes$, I))
            EndIf
          Next
        Case #False
          For I = 1 To Len(MyModes$)
            If FindString(ChannelsJoined()\MyChanModes$, Left(MyModes$, I))
              ChannelsJoined()\MyChanModes$ = RemoveString(ChannelsJoined()\MyChanModes$, Left(MyModes$, I))
              MyModes$ = RemoveString(MyModes$, Left(MyModes$, I))
            EndIf  
          Next
      EndSelect
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.s IRC_GetMyChanModes(TheChannel$) ; Retreive the modes you have for TheChannel$...
  ForEach ChannelsJoined() ; If you have +v and +o, the function would return "ov", or a string
    If ChannelsJoined()\ChannelName$ = TheChannel$ ; containing only the letters of your modes,
      ProcedureReturn ChannelsJoined()\MyChanModes$ ; specific to the channel specified.
    EndIf
  Next
EndProcedure  
  
Procedure.i IRC_UserNick(OldNick$, NewNick$) ; When another person changes nicks, update this change for all userlists, in all channels.
  Protected Result.i = #False
  ForEach ChannelsJoined()
    ForEach ChannelsJoined()\Users()
      If ChannelsJoined()\Users() = OldNick$
        ChannelsJoined()\Users() = NewNick$
        Result = #True
      EndIf
    Next
  Next
  ProcedureReturn Result
EndProcedure

Procedure.i IRC_UserQuit(NickName$) ; Remove a Quitting User from all local userlists he/she exists in.
  Protected Result.i = #False
  ForEach ChannelsJoined()
    ForEach ChannelsJoined()\Users()
      If ChannelsJoined()\Users() = NickName$
        DeleteElement(ChannelsJoined()\Users())
        Result = #True
      EndIf
    Next
  Next
  ProcedureReturn Result
EndProcedure

Procedure.i IRC_EnumNames(TheSocket, TheChannel$) ; Request A List of the NickNames in a specific channel.
  Protected Result.l = #False
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      ClearList(ChannelsJoined()\Users())
      Result = #True
    EndIf
  Next
  Result = IRC_RawText(TheSocket, "NAMES :" + TheChannel$)
  ProcedureReturn Result
EndProcedure 

Procedure.i IRC_EnumTopic(TheSocket, TheChannel$) ; Request the topic info for a channel. response is handled elsewhere
  Protected Result.l = #False
  If IRC_InChannel(TheChannel$) And IRC_RawText(TheSocket, "TOPIC " + TheChannel$)
    Result = #True
  EndIf
  ProcedureReturn Result
EndProcedure
  
Procedure.i IRC_SetTopic(TheSocket, TheChannel$, TheTopic$) ; Sets a new topic for a channel...
  ForEach ChannelsJoined() ; NOTE: We are making sure we have +o or +a in TheChannel before we even get here.
    If ChannelsJoined()\ChannelName$ = TheChannel$
      IRC_RawText(TheSocket, "TOPIC " + TheChannel$ + " :" + TheTopic$)
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i IRC_UpdateTopic(TheSocket, TheChannel$, TheTopic$) ; Update the channel topic in memory...
  ForEach ChannelsJoined() ; ... But only when the server tells us that it's really happened. Again, going to want to check that prior.
    If ChannelsJoined()\ChannelName$ = TheChannel$
      ChannelsJoined()\ChannelTopic$ = TheTopic$
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.s IRC_GetTopic(TheChannel$) ; Retrieve the topic, date, and author we have stored in memory for the Channel.
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      ProcedureReturn ChannelsJoined()\ChannelTopic$ + " Created On: " + ChannelsJoined()\ChannelTopicDate$ + " By: " + ChannelsJoined()\ChannelTopicAuthor$
    EndIf
  Next
  ProcedureReturn "Channel Not Found. Have I Joined That One?"
EndProcedure

Procedure.i IRC_UpdateTopicDetails(TheChannel$, Date_Created$, Creator$) ; Stores the Creator and Timestamp of a Channel Topic.
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      ChannelsJoined()\ChannelTopicDate$ = FormatDate("%yyyy-%mm-%dd @ %hh:%ii:%ss", Val(Date_Created$))
      ChannelsJoined()\ChannelTopicAuthor$ = Creator$
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i IRC_Am_I_Oper_In(TheChannel$) ; Check to see if we (the bot) have the +o (Oper Mode).
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      If FindString(ChannelsJoined()\MyChanModes$, "o")
        ProcedureReturn #True
      Else
        ProcedureReturn #False
      EndIf
    EndIf 
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i IRC_Am_I_Admin_In(TheChannel$) ; Check to see if we (the bot) have the +a (Admin Mode).
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      If FindString(ChannelsJoined()\MyChanModes$, "a")
        ProcedureReturn #True
      Else
        ProcedureReturn #False
      EndIf
    EndIf 
  Next
  ProcedureReturn #False
EndProcedure

Procedure.i IRC_Am_I_Voiced_In(TheChannel$) ; Check to see if we (the bot) have the +v (Voice Mode).
  ForEach ChannelsJoined()
    If ChannelsJoined()\ChannelName$ = TheChannel$
      If FindString(ChannelsJoined()\MyChanModes$, "v")
        ProcedureReturn #True
      Else
        ProcedureReturn #False
      EndIf
    EndIf 
  Next
  ProcedureReturn #False
EndProcedure

Procedure.s IRC_TrimUserSymbols(NickName$) ; Removes characters such as @, ~, &, %, and +. 
  NickName$ = RemoveString(NickName$, "@") ; These chars denote user modes, however they 
  NickName$ = RemoveString(NickName$, "~") ; can complicate enumerating and storing users
  NickName$ = RemoveString(NickName$, "&") ; for use later on when we need to send something
  NickName$ = RemoveString(NickName$, "%") ; to them or in any other way interact with them
  NickName$ = RemoveString(NickName$, "+") ; by their 'actual' nick.
  ProcedureReturn NickName$
EndProcedure 

Procedure.s IRC_GetURLTitle(URLToLookup$) ; Grabs the HTML Code provided by the URL..
  Protected URL_HTML$ = ReceiveHTTPString(URLToLookup$) 
  Protected Title$ = ""
  URL_HTML$ = ReplaceString(URL_HTML$, Chr(10), "")
  URL_HTML$ = ReplaceString(URL_HTML$, Chr(13), "")
  URL_HTML$ = ReplaceString(URL_HTML$, "&amp;", "&")
  URL_HTML$ = ReplaceString(URL_HTML$, "&lt;", "<")
  URL_HTML$ = ReplaceString(URL_HTML$, "&gt;", ">")
  URL_HTML$ = ReplaceString(URL_HTML$, "&#39;", "'")
  URL_HTML$ = ReplaceString(URL_HTML$, "&quot;", #DQUOTE$)
  Title$ = StringBetween(URL_HTML$, "<title>", "</title>") : Debug Title$ 
  Title$ = Trim(Title$)         ; ...and fetches the "<title> tag" contents for the return.
  ProcedureReturn Title$
EndProcedure

Procedure.s IRC_FindUrl(Line_Text$) ; URL Detection. Needs a little work. ==========================
  If FindString(Line_Text$, "http")
    Protected URLStart.i = FindString(Line_Text$, "http")
    Protected URLEnd.i = FindString(Line_Text$, " ", URLStart)
    If URLEnd = 0 : URLEnd = Len(Line_Text$) - URLStart : Else : URLEnd - URLStart : EndIf
    Protected URLResult$ = Mid(Line_Text$, URLStart, URLEnd + 1)
    If URLResult$ = "" : URLResult$ = Line_Text$ : EndIf
    If ( ( Right(URLResult$, 1) <> "/" ) And ( Not FindString(URLResult$, "?") ) ) : URLResult$ = URLResult$ + "/" : EndIf
    URLResult$ = RemoveString(URLResult$, " ")
    Debug "Found URL: " + URLResult$
    ProcedureReturn URLResult$
  EndIf
  ProcedureReturn ""  
EndProcedure

Procedure IRC_AutoJoinChannels() ; Auto-Join a string-list of channel names...
  ForEach AutoJoinListItem() ; Currently pre-populating this list manually, using code at startup.
    IRC_RawText(IRCSocket, "JOIN :" + AutoJoinListItem())
    Delay(100)
  Next
  IRC_RawText(IRCSocket, "LIST")
  Delay(100)
EndProcedure

Procedure BotCommand(TheSocket, EntireLine$) ; Process a line that was sent prefixed with the Command ID FIX MEEEEEEE!!!!!!11!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  ;=======================================Init Variables Section=========================================
  Protected CommandType.i
  Protected Command$ = ""
  Protected Remainder$ = ""
  Protected Respond_To$ = IRC_GetChannel(EntireLine$) ; Always public, ALWAYS
  Protected pHandle.l
  Protected CommandChannel$ = IRC_GetChannel(EntireLine$)
  Protected Who_From$ = IRC_GetFrom(EntireLine$)
  
  ;======================================Separate Command and Args=======================================
  If Not FindString(IRC_GetText(EntireLine$), " ")                    ;there are no Args, only '!command'
    Command$ = RemoveString(IRC_GetText(EntireLine$), CommandIDChar$)
  Else                                                     ;Command Text contains Arguements / Parameters
    Command$ = StringBetween(IRC_GetText(EntireLine$), CommandIDChar$, " ")
    Remainder$ = RemoveString(IRC_GetText(EntireLine$), CommandIDChar$+Command$+" ") 
  EndIf
  
  Respond_To$ = IRC_GetChannel(EntireLine$)
  
  ;============================act based upon which command we are dealing with===========================
  Select Command$
    Case "quit"
      IRC_RawText(TheSocket, "QUIT :" + Remainder$)
    Case "echo"
      IRC_SendText(TheSocket, Respond_To$, "'"+Remainder$+"'")
    Case "topic"
      If Remainder$ <> ""
        If CommandChannel$ <> "" And ( ( IRC_Am_I_Oper_In(CommandChannel$) ) Or ( IRC_Am_I_Admin_In(CommandChannel$) ) )
          IRC_SetTopic(TheSocket, CommandChannel$, Remainder$)
        EndIf
      Else
        IRC_SendText(TheSocket, Respond_To$, "Topic for " + CommandChannel$ + " is: "+#IRC_BOLD_TEXT+IRC_GetTopic(IRC_GetChannel(EntireLine$)))
      EndIf
    Case "modes"
      IRC_SendText(TheSocket, Respond_To$, "My Modes in this channel: " + IRC_GetMyChanModes(IRC_GetChannel(EntireLine$)))
    Case "color"
      ColorCode = Val(Remainder$)
    Case "nslookup"
      IRC_SendText(TheSocket, Respond_To$, "'"+Remainder$ + "' -> " + HostnameToIP(Trim(Remainder$)))
  EndSelect
 ;====================================================================================================
EndProcedure

Procedure IRC_ScanLine(TheSocket, EntireLine$, TimeDate.i, PrintOnly=#False) ; Line gets processed to handle events & record line datas. Expand for ... a fun read.
  ; =======================================================================================================
  ; [Hi!] The general Idea is that this is where all of the incoming Lines of IRC text pass through first.;
  ; ..... This procedure is designed to save you the hassle of Identifying, Creating, and Enumerating the ;
  ; ... variables which are necessary to communicate on IRC.  Hopefully when done, you won't need to know ;
  ; .............. much at all about IRC Protocol and still be able to develp a bot, using this as a base.;
  ;[INITIAL VARIABLES SECTION]============================================================================;
  Protected Line_From$ = IRC_GetFrom(EntireLine$) ; Who Sent It. (Their NickName, not their UserName).;
  Protected Line_Sent_To$ = IRC_GetTo(EntireLine$) ; Who it was sent to.  Almost always you or a #channel.;
  Protected Line_Text$ = IRC_GetText(EntireLine$) ; The Specific Text of the Line with the actual message.;
  Protected Line_TheChannel$ = IRC_GetChannel(EntireLine$) ; Which channel, if any, this line happened in.;
  Protected Line_ID_Code$ = IRC_GetCode(EntireLine$) ; IRC protocol-specific ID, tells us the line's type.;
  Protected Line_From_UserHost$ = IRC_GetFromHost(EntireLine$) ; The senders hostname, relative to server.;
  Protected Line_From_UserName$ = IRC_GetFromUsername(EntireLine$) ; The senders username, (Not NickName).;
  Protected Line_From_FullStr$ = IRC_GetFullFrom(EntireLine$) ; Full info for sender: i.e. Nick!User@Host.;
  Protected Line_My_Chan_Modes$ = IRC_GetMyChanModes(Line_TheChannel$) ; Existing Modes for this Channel$.;
  Protected Line_Param_4$ = IRC_GetP4(EntireLine$) ; .....................................................;
  Protected Line_Param_5$ = IRC_GetP5(EntireLine$) ; .....................................................;
  Protected Line_Param_6$ = IRC_GetP6(EntireLine$) ; .....................................................;
  Protected Line_TimeStamp.i ; We take note of the full date and time in case it is needed later.;
  Protected Line_Type.i ; Bot-specific flag identifies whether line was sent publicly or privately to bot.;
  Protected Line_Respond_To$ ; To whom/what should we reply? This is determined by the Line_Type variable.;
  ;=======================================================================================================/
  If TimeDate <> 0 : Line_TimeStamp = TimeDate : Else : TimeDate = Date() : EndIf
  ;[DETERMINE LINE_TYPE FLAG FOR THE LINE]================================================================;
  If Line_TheChannel$ = Line_Sent_To$ ; The Line's Channel matches the Line's Recipient > Public/#Channel.;
    Line_Respond_To$ = Line_Sent_To$ ; So, we should be sending our responses to the same channel as that.;
    Line_Type = #AFK_PRIVMSG_CHANNEL ; Set the Line_Type Flag according to what we just found out above ^.;
  Else ; ........................................ If not, then this PRIVMSG was sent to me as a Direct PM.;
    Line_Respond_To$ = Line_From$ ; Then, we should respond to the nick who Private Messaged the Line.;
    Line_Type = #AFK_PRIVMSG_PRIVATE  ; Set Line_Type Flag, tagging this line as a privately received one.;
  EndIf ; ................................................................................................;
  ;==============================================================[/DETERMINE LINE_TYPE FLAG FOR THE LINE]=/
  
  If PrintOnly ; If this is true, we will simply re-print this line to the console, and not re-analyse it.;
    
    IRC_ConsolePrintLine(TheSocket, Line_From$, Line_Sent_To$, Line_Text$, Line_TheChannel$, 
                         Line_ID_Code$, Line_From_UserHost$, Line_From_UserName$, Line_From_FullStr$,
                         Line_My_Chan_Modes$, Line_Param_6$, Line_Param_5$, Line_Param_4$, Line_TimeStamp,
                         Line_Type, Line_Respond_To$, BotNick$)
    
    ProcedureReturn
    
  EndIf 
  
  ;[STATISTICS AND COUNTERS]==============================================================================;
  RecvLines = RecvLines + 1 ; ....................... These variables contain misc. global bot statistics.;
  ;============================================================================[/STATISTICS AND COUNTERS]=/
  
  ;[IDENTIFY THE TYPE OF LINE AND HANDLE DATA]============================================================;
  Select Line_ID_Code$ ; ....................................................This is the identifying code.;
    Case "004" ; 004 Contains server hostname we connected to. Sometimes different than the network addrs.;
      IRC_Host$ = StringField(Line_Text$, 1, " ") ; ........... Save hostname to a Global string Variable.;
  ; -----------------------------------------------------------------------------------------------[/004]-;
    Case "303" ; ................................................... This is the reply to an ISON command.;
      ; ..................... If Line_Text$ <> "" And Line_Text$ = "The_user" : The_user is indeed online.;
  ; -----------------------------------------------------------------------------------------------[/303]-;
    Case "305" ; ................. This is the server confirming for us that we are no longer set to AWAY.;
      Bot_Away_Status = #False ; .............................................. Update the local variable.;
  ; -----------------------------------------------------------------------------------------------[/305]-;
    Case "306" ; ..................... This is the server confirming for us that we have been set to AWAY.;
      Bot_Away_Status = #True ; ............................................... Update the local variable.;
  ; -----------------------------------------------------------------------------------------------[/306]-;
    Case "311"
      If Line_Sent_To$ = BotNick$ And Line_Param_4$ = BotNick$
        BotIDFull$ = Line_Param_4$+"!"+Line_Param_5$+"@"+Line_Param_6$
      EndIf
    Case "321"
      ClearList(AvailableChannels())
    Case "322"
      AddElement(AvailableChannels())
      AvailableChannels()\ChannelName$ = Line_Param_4$
      AvailableChannels()\Description$ = Line_Text$
    Case "323"
      TotalChannelsAvailable = ListSize(AvailableChannels())
    Case "332" ; ..... This ID Indicates that the line will contain the topic of #channel Line_TheChannel.$
      IRC_UpdateTopic(TheSocket, Line_TheChannel$, Line_Text$) ; Save that information to Channels List().;
  ; -----------------------------------------------------------------------------------------------[/332]-;
    Case "333" ; ........................ This line will contain the Datestamp that the topic was created.;
      IRC_UpdateTopicDetails(Line_TheChannel$,StringField(Line_Text$,3," "),StringField(Line_Text$,2," "));
  ; -----------------------------------------------------------------------------------------------[/333]-;
    Case "353" ; ........................ Server sending some or all of the NickNames idling in a channel.;
      IRC_UpdateUsersInChan(Line_TheChannel$, IRC_TrimUserSymbols(Line_Text$)) ; Add users to Local Lists.;
  ; -----------------------------------------------------------------------------------------------[/353]-;
    Case "376"
      IRC_RawText(TheSocket, "WHOIS " + BotNick$)
    Case "JOIN" ; ...................... You have joined, or someone else has joined a channel you are in.;
      If Line_From$ = BotNick$ ; ................................ If it was me who joined the channel.;
        IRC_UpdateChanList(Line_TheChannel$) ; .... Make sure that channel is in my ChannelsJoined() List.;
        IRC_UpdateChanMasterRecipients(Line_TheChannel$)
      Else ; ....................................................... But if instead it was someone else...;
        IRC_EnumNames(TheSocket, Line_TheChannel$) ; .... Ask server to send new list of Nicks in channel.;
        IRC_UpdateUsersInChan(Line_TheChannel$, Line_From$) ; .......... Add the new User(s) to lists.;
      EndIf ; ............................................................................................;
  ; ----------------------------------------------------------------------------------------------[/JOIN]-;
    Case "QUIT" ; ............................ Somebody (You or another user) Has QUIT IRC (Disconnected).;
      If Line_From$ <> BotNick$ ; ............. If it was any other user besides myself who just quit.;
        IRC_UserQuit(Line_From$) ; .................. Remove that user from all of my User/Chan lists.;
      EndIf ; ................... I do not check if it was me who quit, because quitting ends the program.;
  ; ----------------------------------------------------------------------------------------------[/QUIT]-;
    Case "PART" ; ......................... When anyone has left (parted from) a channel. Oppsite of JOIN.;
      If Line_From$ = BotNick$ ; .................... When it is me, the bot who parted the channel...;
        IRC_RemoveChanList(Line_TheChannel$) ; ....... We'll remove that whole channel from our chan list.;
        IRC_RemoveChanMasterRecipients(Line_TheChannel$)
      Else ; ............................................................... As far as anyone else goes...;
        IRC_EnumNames(TheSocket, Line_TheChannel$) ; . Get a fresh copy of the Nick List for that channel.;
      EndIf ; ............................................................................................;
  ; ----------------------------------------------------------------------------------------------[/PART]-;
    Case "MODE" ; ........................................... Indicates a /mode change (+/-) has occurred.;
      If Line_Param_4$ = BotNick$ ; ......... If the MODE commmand was directed at us, read the changes.;
        IRC_UpdateMyChanModes(Line_TheChannel$, Line_Param_5$) ; ... save changes in channel list.;
      EndIf ; ............................................................................................;
  ; ----------------------------------------------------------------------------------------------[/MODE]-;
    Case "NICK" ; ............................................. You or someone else has changed NickNames.;
      IRC_UserNick(Line_From$, Line_Text$) ; ....... Search and replace that users nick in local list.;
  ; ----------------------------------------------------------------------------------------------[/NICK]-;
    Case "TOPIC" ; ......................................... There has been a change to the channel topic.;
      IRC_EnumTopic(TheSocket, Line_TheChannel$) ; .................... Request new topic from the server.;
  ; ---------------------------------------------------------------------------------------------[/TOPIC]-;
    Case "INVITE" ; ......................................... Someone has sent an invite to a new Channel.;
      IRC_RawText(TheSocket, "JOIN :" + Line_Text$) ; .............. So we go ahead, and join the channel.;
  ; --------------------------------------------------------------------------------------------[/INVITE]-;
    Case "NOTICE" ; .............. Contains alerts, and other useful information. Typically from services.;
      If Line_From$ = "NickServ" ; ... Make Sure its from NickServ, and not some random guy.;
        If FindString(EntireLine$, "IDENTIFY") ; .... A simple way to tell if NickServ wants us to log in.;
          IRC_RawText(IRCSocket, "PRIVMSG NickServ :IDENTIFY " + NickServPass$) ;  Send Login to the Host.;
        ElseIf FindString(UCase(EntireLine$), "PASSWORD ACCEPTED") ; .. If we see this, our login went OK.;
          IRC_AutoJoinChannels() ; Now that we are logged in (probably) we can auto-join our channel list.;
        EndIf ; ..........................................................................................;
      EndIf ; ............................................................................................;
  ; --------------------------------------------------------------------------------------------[/NOTICE]-;
    Case "PRIVMSG" ; .......................... A typical IRC Message Line, could be coming from anywhere.;
      If Left(Line_Text$, 1) = CommandIDChar$ ; ................. if CommandID is present, check as a cmd.;
        BotCommand(TheSocket, EntireLine$) ; ................................. Try to execute the command.;
      EndIf ; ***NOTE: Command System is barely operational at this time, just enough to test and develop.;
  ; -------------------------------------------------------------------------------------------[/PRIVMSG]-;    
  EndSelect ; ............................................................................................;
  ;==========================================================[/IDENTIFY THE TYPE OF LINE AND HANDLE DATA]=/
  
  IRC_ConsolePrintLine(TheSocket, Line_From$, Line_Sent_To$, Line_Text$, Line_TheChannel$, 
                       Line_ID_Code$, Line_From_UserHost$, Line_From_UserName$, Line_From_FullStr$,
                       Line_My_Chan_Modes$,Line_Param_6$, Line_Param_5$, Line_Param_4$, Line_TimeStamp,
                       Line_Type, Line_Respond_To$, BotNick$)
      
  If (IRC_FindUrl(Line_Text$) <> "") And (Line_From$ <> IRC_Host$)
    IRC_SendText(TheSocket, Line_Respond_To$, "[" + Line_From$ + "] -> " + #DQUOTE$ + IRC_GetURLTitle(IRC_FindUrl(Line_Text$)) + #DQUOTE$)
  EndIf
  
EndProcedure

Procedure IRC_GetLine(TheSocket) ; Rapidly sort through received text, breaking it into lines, and queueing.
  Protected RecvBuffer.s = Space(Socket_Buffer_Size)
  Protected BytesRecv.i = #SOCKET_ERROR
  Protected TempString$ = ""
  Protected ReturnString$ = ""
  Protected Line.s = ""
  While BytesRecv = #SOCKET_ERROR
    BytesRecv = recv_(TheSocket, @RecvBuffer, Len(RecvBuffer), 0)
    If BytesRecv = #WSAECONNRESET
      PrintN("Connection Reset.")
      closesocket_(TheSocket)
      Connected = 0
      ShutdownSockets(1)
      Input()
      End
    ElseIf BytesRecv <= 0
      Connected = 0
      ShutdownSockets(1)
      PrintN("Disconnected. Program Exiting...")
      Delay(2000)
      End
    Else
      ;Debug "Recv: " + BytesRecv + " Bytes."
      RecvBytes = RecvBytes + BytesRecv
      TempString$ = Trim(PeekS(@RecvBuffer))
      ReplaceString(TempString$, Chr(13), Chr(10))
      ReplaceString(TempString$, Chr(10)+Chr(10), Chr(10))
      ReturnCount.i = CountString(TempString$, Chr(10))
      For K = 1 To ReturnCount
        Line.s = RemoveString(RemoveString(StringField(TempString$, k, Chr(10)), Chr(10)), Chr(13))
        If FindString(Line, "PING :", 0)
          IRC_RawText(TheSocket, ReplaceString(Line, "PING :", "PONG :",0))
        Else
          AddElement(ReadLines())
          ReadLines() = Line
        EndIf 
      Next
    EndIf
    If ListSize(ReadLines()) > 0
      ForEach ReadLines()
        Debug "Scan: " + ReadLines()
        IRC_ScanLine(TheSocket, ReadLines(), Date())
        AddElement(BackLogLines())
        BackLogLines()\EntireLineString$ = ReadLines()
        BackLogLines()\TimeStamp = Date()
        DeleteElement(ReadLines())
      Next
    EndIf
  Wend
EndProcedure

Procedure IRC_Login(TheSocket, Nickname.s, Username.s, Password.s="") ; send the user+nick information, and store the NickServ Password
  If TheSocket <> #INVALID_SOCKET
    IRC_RawText(TheSocket, "NICK :" + Nickname)
    IRC_RawText(TheSocket, "USER " + UserName + " " + Get_Local_FQDN() + " " + IRC_Server$ + " :AFK-Operator v" + IRC_Bot_Version$)
    If Password <> ""
      NickServPass$ = Password
    EndIf
  EndIf
EndProcedure

Procedure ReadLoop(*null) ; read a new line every 1 ms
  Repeat
    IRC_GetLine(IRCSocket)
    Delay(1)
  ForEver
EndProcedure

Procedure DebugShit() ; I'm just here to help us keep an eye on things we aren't completely sure about yet.
  ;ForEach AvailableChannels()
  ;  Debug AvailableChannels()\ChannelName$
  ;Next
  Debug "Total Bytes Sent: " + SentBytes
  Debug "Total Bytes Recv: " + RecvBytes
  Debug "Total Lines Sent: " + SentLines
  Debug "Total Lines Recv: " + RecvLines
EndProcedure

Procedure ConsoleInput(TheSocket, Console_Input$) ; Console Command Input
  Protected Command$ = StringField(Console_Input$, 1, " ")
  Protected Param1$ = StringField(Console_Input$, 2, " ")
  Protected Param2$ = StringField(Console_Input$, 3, " ")
  Protected Param3$ = StringField(Console_Input$, 4, " ")
  Protected RemainderText$ = ""
  If Command$ <> ""
    Select LCase(Command$)
      Case "/me"
        RemainderText$ = RemoveString(Console_Input$, "/me ")
        IRC_SendText(TheSocket, "#cyberghetto", Chr(1)+"ACTION "+RemainderText$+Chr(1))
      Case "/raw"
        RemainderText$ = RemoveString(Console_Input$, "/raw ")
        If RemainderText$ <> ""
          IRC_RawText(IRCSocket, RemainderText$)
        EndIf 
      Case "/list"
        IRC_RawText(IRCSocket, "LIST")
      Case "/quit"
        Protected QuitLine$ = "QUIT"
        RemainderText$ = RemoveString(Console_Input$, "/quit ")
        If RemainderText$ <> "" : QuitLine$ = QuitLine$ + " " + RemainderText$ : EndIf
        IRC_RawText(IRCSocket, QuitLine$)
      Case "/msg"
        If Param1$ <> ""
          RemainderText$ = Trim(RemoveString(Console_Input$, "/msg " + Param1$))
          If Param1$ <> "" And RemainderText$ <> ""
            Debug "Sending '"+RemainderText$+"' to '" + Param1$ + "'"
            IRC_SendText(IRCSocket, Param1$, RemainderText$)
          EndIf
        EndIf 
      Case "/join"
        If Param1$ <> ""
          IRC_RawText(IRCSocket, "JOIN " + Param1$)
        EndIf 
      Case "/part"
        If Param1$ <> ""
          IRC_RawText(IRCSocket, "PART " + Param1$)
        EndIf
      Case "/focus"
        FocusChannel$ = StringField(Console_Input$, 2, " ")
        If IRC_InChannel(FocusChannel$) Or IRC_FindMasterRecipients(FocusChannel$)
          UI_Focused_Channel$ = FocusChannel$
          UI_ReDraw(IRCSocket)
        Else
          IRC_ConsolePrintLine(TheSocket, BotNick$, BotNick$, "Error: Not in channel", "", "", "", "", "", "", "", "", "", Date(), 0, "", BotNick$)
        EndIf 
      Case "/home"
        UI_Focused_Channel$ = ""
        UI_ReDraw(IRCSocket)
      Case "/test"
        DebugShit()
      Default
        If UI_Focused_Channel$ <> "" And ((IRC_InChannel(UI_Focused_Channel$)) Or (IRC_FindMasterRecipients(UI_Focused_Channel$)))
          IRC_SendText(IRCSocket, UI_Focused_Channel$, Console_Input$)
        Else
          ; Die Motherfucker
        EndIf
    EndSelect
  EndIf 
  If Len(Console_Input$) > UI_ConsoleBufferWidth()
    Debug "Length exceeded, redrawing."
    UI_ReDraw(IRCSocket)
  EndIf
EndProcedure

Procedure LoadPrefs() ; Create Command List, Get Auto-Join channels List, etc.
  ;Eventually these items will be saved, And loaded in at startup.
  AddElement(AutoJoinListItem()) : AutoJoinListItem() = "#afkBot"
  AddElement(AutoJoinListItem()) : AutoJoinListItem() = "#bots"
  
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/raw"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/list"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/quit"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/msg"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/join"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/part"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/focus"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/home"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/test"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/mode"
  AddElement(UI_AvailableCommands()) : UI_AvailableCommands() = "/me"
  SortList(UI_AvailableCommands(), #PB_Sort_Ascending)
EndProcedure

Procedure ReDrawInput(Console_Input$)
  UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
  For I = 1 To UI_ConsoleBufferWidth()-1
    Print(" ")
  Next
  UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
  If Len(Console_Input$) > UI_ConsoleBufferWidth()-8
    Print(">> .." + Right(Console_Input$, UI_ConsoleBufferWidth()-6))
  Else
    Print(">> "+Console_Input$)
  EndIf 
EndProcedure

Procedure Main() ; Main Input / Program Looop
  Protected InputMaxLen.i = UI_ConsoleBufferWidth()-8
  Protected FocusLabel$ = ""
  OpenConsole() 
  ConsoleTitle("AFKBot")

  UI_SetConsoleBufferSize(GetStdHandle_(#STD_OUTPUT_HANDLE), UI_TotalWidth, UI_TotalHeight)
  Delay(250) ; Give the window a little time to catch up
  hwnd.l = FindWindow_(0, "AFKBot")
  If hwnd <> 0 : ShowWindowAsync_(hWnd,#SW_SHOWMAXIMIZED) : EndIf
  If InitializeSockets()
    UI_ConsoleBufferLocate(0, 0)
    While UI_LinesInBuffer < UI_TotalHeight-1
      PrintN("                               | ")
      UI_LinesInBuffer = UI_LinesInBuffer + 1
    Wend
    IRCSocket = Create_Socket_Connect(IRC_Server$, IRC_Port)
    If IRCSocket <> #INVALID_SOCKET
      CreateThread(@ReadLoop(), 0)
      IRC_Login(IRCSocket, BotNick$, BotUser$, NickServPass$)
    EndIf
    Repeat
      KeyPressed$ = Inkey()
      If KeyPressed$ <> ""
        If KeyPressed$ = #UI_PASTE
          ClipText$ = GetClipboardText()
          If ClipText$ <> ""
            Console_Input$ = Console_Input$ + ClipText$
          EndIf
          ReDrawInput(Console_Input$)
        ElseIf KeyPressed$ = #UI_ESC
          If Console_Input$ = ""
            Console_Input$ = "/quit Leaving."
          Else 
            Console_Input$ = ""
          EndIf
          ReDrawInput(Console_Input$)    
        ElseIf KeyPressed$ = #TAB$
          If ( Not FindString(Console_Input$, " ") ) And (Left(Console_Input$, 1) = "/")
            LastElement(UI_AvailableCommands())
            LastCommand$ = UI_AvailableCommands()
            FirstElement(UI_AvailableCommands())
            ForEach UI_AvailableCommands()
              If UI_AvailableCommands() = Console_Input$
                If Console_Input$ = LastCommand$
                  FirstElement(UI_AvailableCommands())
                Else
                  NextElement(UI_AvailableCommands())
                EndIf 
                Console_Input$ = UI_AvailableCommands()
              ElseIf Left(UI_AvailableCommands(), Len(Console_Input$)) = Console_Input$
                Console_Input$ = UI_AvailableCommands()
              EndIf
            Next
          EndIf  
          If FindString(Console_Input$, "/part ")
            LastChannelInList.i = LastElement(ChannelsJoined())
            LastChannelInList$ = ChannelsJoined()\ChannelName$
            FirstElement(ChannelsJoined())
            ForEach ChannelsJoined()
              If FindString(Console_Input$, " ")
                LastWord.i = CountString(Console_Input$, " ") + 1
                LastWord$ = StringField(Console_Input$, LastWord, " ")
              EndIf
              If LastWord$ = ChannelsJoined()\ChannelName$ 
                If LastWord$ = LastChannelInList$ : FirstElement(ChannelsJoined()) : Else : NextElement(ChannelsJoined()) : EndIf
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, ChannelsJoined()\ChannelName$)
              ElseIf Left(ChannelsJoined()\ChannelName$, Len(LastWord$)) = LastWord$
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, ChannelsJoined()\ChannelName$)
                Continue
              EndIf
            Next
          ElseIf FindString(Console_Input$, "/focus ")
            LastRecipInList.i = LastElement(Master_Recipients())
            LastRecipInList$ = Master_Recipients()
            FirstElement(Master_Recipients())
            ForEach Master_Recipients()
              If FindString(Console_Input$, " ")
                LastWord.i = CountString(Console_Input$, " ") + 1
                LastWord$ = StringField(Console_Input$, LastWord, " ")
              EndIf
              If LastWord$ = Master_Recipients()
                If LastWord$ = LastRecipInList$ : FirstElement(Master_Recipients()) : Else : NextElement(Master_Recipients()) : EndIf
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, Master_Recipients())
              ElseIf Left(Master_Recipients(), Len(LastWord$)) = LastWord$
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, Master_Recipients())
                Continue
              EndIf
            Next
          ElseIf FindString(Console_Input$, "/join ") And ListSize(AvailableChannels()) > 0
            LastChannelInList.i = LastElement(AvailableChannels())
            LastChannelInList$ = AvailableChannels()\ChannelName$
            FirstElement(AvailableChannels())
            ForEach AvailableChannels()
              If FindString(Console_Input$, " ")
                LastWord.i = CountString(Console_Input$, " ") + 1
                LastWord$ = StringField(Console_Input$, LastWord, " ")
              EndIf
              If LastWord$ = AvailableChannels()\ChannelName$ 
                If LastWord$ = LastChannelInList$ : FirstElement(AvailableChannels()) : Else : NextElement(AvailableChannels()) : EndIf
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, AvailableChannels()\ChannelName$)
              ElseIf Left(AvailableChannels()\ChannelName$, Len(LastWord$)) = LastWord$
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, AvailableChannels()\ChannelName$)
                Continue
              EndIf
            Next
          ElseIf FindString(Console_Input$, "/msg ")
            LastUserInList.i = LastElement(Master_Recipients())
            LastUserInList$ = Master_Recipients()
            FirstElement(Master_Recipients())
            ForEach Master_Recipients()
              If FindString(Console_Input$, " ")
                LastWord.i = CountString(Console_Input$, " ") + 1
                LastWord$ = StringField(Console_Input$, LastWord, " ")
              EndIf
              If LastWord$ = Master_Recipients()
                If LastWord$ = LastUserInList$ : FirstElement(Master_Recipients()) : Else : NextElement(Master_Recipients()) : EndIf
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, Master_Recipients())
              ElseIf Left(Master_Recipients(), Len(LastWord$)) = LastWord$
                Console_Input$ = ReplaceString(Console_Input$, LastWord$, Master_Recipients())
                Continue
              EndIf
            Next
          EndIf
          ReDrawInput(Console_Input$)       
        ElseIf KeyPressed$ = #CR$
          LR = 0
          UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
          For I = 1 To UI_ConsoleBufferWidth()-1
            Print(" ")
          Next
          UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
          ConsoleInput(IRCSocket, Console_Input$)
          UI_ConsoleBufferLocate(0,UI_TotalHeight-1)
          AddElement(Rec_Sent())
          Rec_Sent() = Console_Input$
          LastElement(Rec_Sent())
          Console_Input$ = ""
          Current$ = ""
          ForEach Rec_Sent()
            If Rec_Sent() <> Current$
              Current$ = Rec_Sent()
            Else
              DeleteElement(Rec_Sent())
            EndIf
          Next
        ElseIf KeyPressed$ = #UI_BACKSPACE
          Console_Input$ = Left(Console_Input$, Len(Console_Input$)-1)
          ReDrawInput(Console_Input$)         
        Else
          Console_Input$ + KeyPressed$
          UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
          For I = 1 To UI_ConsoleBufferWidth()-1
            Print(" ")
          Next
          UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
          If Len(Console_Input$) > UI_ConsoleBufferWidth()-8
            Print(">> .." + Right(Console_Input$, UI_ConsoleBufferWidth()-6))
          Else
            Print(">> "+Console_Input$)
          EndIf 
        EndIf
        Debug "Input: " + Console_Input$
      ElseIf RawKey()
        Debug "Raw: "+Str(RawKey())
        Select RawKey()
          Case 38 ; Up
            If ListSize(Rec_Sent()) > 0
              PreviousElement(Rec_Sent())
              Console_Input$ = Rec_Sent()
              UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
              Print(">> "+Console_Input$)
              ReDrawInput(Console_Input$)
            EndIf
          Case 40 ; Down
            If ListSize(Rec_Sent()) > 0
              NextElement(Rec_Sent())
              Console_Input$ = Rec_Sent()
              UI_ConsoleBufferLocate(0, UI_ConsoleBufferHeight()-1)
              Print(">> "+Console_Input$)
              ReDrawInput(Console_Input$)
            EndIf
        EndSelect
      EndIf
      If UI_Focused_Channel$ <> "" : FocusLabel$ = UI_Focused_Channel$ : Else : FocusLabel$ = IRC_Host$ : EndIf
      Delay(1)
      ConsoleTitle("("+FocusLabel$ + ")  |  Lines/Bytes -> Sent: ("+Str(SentLines)+"/"+Str(SentBytes)+ ") Received: ("+Str(RecvLines)+"/"+Str(RecvBytes)+")  |")
    Until Connected = 0
  EndIf
EndProcedure

LoadPrefs()
Main()
; IDE Options = PureBasic 5.31 (Windows - x86)
; ExecutableFormat = Console
; CursorPosition = 23
; Folding = 9DcAAAAAAQA-
; EnableThread
; EnableXP
; EnableAdmin
; Executable = sb_.exe
; EnablePurifier
; EnableCompileCount = 2750
; EnableBuildCount = 83