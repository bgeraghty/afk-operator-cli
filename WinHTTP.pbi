Import "winhttp.lib"
  WinHttpOpen(pwszUserAgent.p-unicode, dwAccessType.l, *pwszProxyName, *pwszProxyBypass, dwFlags.l)
  WinHttpConnect(hSession, pswzServerName.p-unicode, nServerPort.l, dwReserved.l)
  WinHttpSetOption(hInternet, dwOption.l, *lpBuffer, dwBufferLength.l)
  WinHttpSetCredentials(hInternet, AuthTargets.l, AuthScheme.l, pwszUserName.p-unicode, pwszPassword.p-unicode, *pAuthParams)
  WinHttpOpenRequest(hConnect, pwszVerb.p-unicode, pwszObjectName.p-unicode, *pwszVersion, *pwszReferrer, *ppwszAcceptTypes, dwFlags.l)
  WinHttpSendRequest(hRequest, pwszHeaders.p-unicode, dwHeadersLength.l, *lpOptional, dwOptionalLength.l, dwTotalLength.l, dwContext.l)
  WinHttpReceiveResponse(hRequest, *lpReserved)
  WinHttpAddRequestHeaders(hRequest, pwszHeaders.p-unicode, dwHeadersLength.l, dwModifiers.l)
  WinHttpQueryHeaders(hRequest, dwInfoLevel.l, *pwszName, *lpBuffer, *lpdwBufferLength, *lpdwIndex)
  WinHttpQueryDataAvailable(hRequest, *lpdwNumberOfBytesAvailable)
  WinHttpReadData(hRequest, *lpBuffer, dwNumberOfBytesToRead.l, *lpdwNumberOfBytesRead)
  WinHttpCrackUrl(pwszUrl.p-unicode, dwUrlLength.l, dwFlags.l, *lpUrlComponents)
  WinHttpCloseHandle(hInternet)
EndImport

Enumeration
  #INTERNET_SCHEME_HTTP                   = 1
  #INTERNET_SCHEME_HTTPS                  = 2
  #INTERNET_DEFAULT_HTTP_PORT             = 80
  #INTERNET_DEFAULT_HTTPS_PORT            = 443
  #WINHTTP_NO_PROXY_NAME                  = 0
  #WINHTTP_NO_PROXY_BYPASS                = 0
  #WINHTTP_NO_REFERER                     = 0
  #WINHTTP_NO_HEADER_INDEX                = 0
  #WINHTTP_DEFAULT_ACCEPT_TYPES           = 0
  #WINHTTP_ACCESS_TYPE_DEFAULT_PROXY      = 0
  #WINHTTP_HEADER_NAME_BY_INDEX           = 0
  #WINHTTP_AUTH_TARGET_SERVER             = 0
  #WINHTTP_AUTH_TARGET_PROXY              = 1
  #WINHTTP_AUTH_SCHEME_BASIC              = 1
  #WINHTTP_AUTH_SCHEME_NTLM               = 2
  #WINHTTP_AUTH_SCHEME_PASSPORT           = 4
  #WINHTTP_AUTH_SCHEME_DIGEST             = 8
  #WINHTTP_AUTH_SCHEME_NEGOTIATE          = 16
  #WINHTTP_OPTION_REDIRECT_POLICY                         = 88
  #WINHTTP_OPTION_REDIRECT_POLICY_NEVER                   = 0
  #WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP  = 1
  #WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS                  = 2
  #WINHTTP_QUERY_STATUS_CODE              = 19
  #WINHTTP_QUERY_RAW_HEADERS_CRLF         = 22
  #WINHTTP_QUERY_CONTENT_ENCODING         = 29
  #WINHTTP_QUERY_LOCATION                 = 33
  #WINHTTP_QUERY_FLAG_NUMBER              = $20000000
  #WINHTTP_OPTION_USERNAME                = $1000
  #WINHTTP_OPTION_PASSWORD                = $1001
  #WINHTTP_FLAG_REFRESH                   = $00000100
  #WINHTTP_FLAG_SECURE                    = $00800000
  #WINHTTP_ADDREQ_FLAG_ADD                = $20000000
EndEnumeration

Prototype ReceiveHTTPStart(CallbackID, hRequest)
Prototype ReceiveHTTPProgress(CallbackID, lBytesReceived, lSize, lElapsedTime)
Prototype ReceiveHTTPEnd(CallbackID, lRetVal, lBytesReceived, lSize, lElapsedTime)

Procedure ReceiveHTTPMemory(URL$, RequestType$ = "GET", ReturnHeader = #False, Username$ = "", Password$ = "", HeaderData$ = "", OptionalData$ = "", UserAgent$ = "WinHTTP - PureBasic", CallbackID = 0, CallbackStart.ReceiveHTTPStart = 0, CallbackProgress.ReceiveHTTPProgress = 0, CallbackEnd.ReceiveHTTPEnd = 0)
  Protected lpUrlComponents.URL_COMPONENTS\dwStructSize = SizeOf(URL_COMPONENTS)
  Protected lStatusCode.l, lContentLen.l, lRedirectPolicy.l = #WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS, lLongSize.l = SizeOf(Long)
  Protected hInternet, hConnect, hRequest, lRetVal, lBytesRead, lReadUntilNow, lBufSize, lStartTime, lResult
  Protected lPort, lFlags, sDomain$, sPath$, sQuery$, *OptionalBuffer, OptionalLength, *MemoryBuffer, MemoryLength
  Static hSession
  
  lStartTime = ElapsedMilliseconds()
  lpUrlComponents\dwSchemeLength = -1
  lpUrlComponents\dwHostNameLength = -1
  lpUrlComponents\dwUrlPathLength = -1
  lpUrlComponents\dwExtraInfoLength = -1
  
  If WinHttpCrackUrl(URLEncoder(URL$), #Null, #Null, @lpUrlComponents)
    Select lpUrlComponents\nScheme
      Case #INTERNET_SCHEME_HTTP
        lPort = #INTERNET_DEFAULT_HTTP_PORT
        lFlags = #WINHTTP_FLAG_REFRESH
      Case #INTERNET_SCHEME_HTTPS
        lPort = #INTERNET_DEFAULT_HTTPS_PORT
        lFlags = #WINHTTP_FLAG_REFRESH | #WINHTTP_FLAG_SECURE
    EndSelect
    
    If lPort And lFlags
      If lpUrlComponents\lpszHostName And lpUrlComponents\dwHostNameLength
        sDomain$ = PeekS(lpUrlComponents\lpszHostName, lpUrlComponents\dwHostNameLength, #PB_Unicode)
      EndIf
      If lpUrlComponents\lpszUrlPath And lpUrlComponents\dwUrlPathLength
        sPath$ = PeekS(lpUrlComponents\lpszUrlPath, lpUrlComponents\dwUrlPathLength, #PB_Unicode)
      EndIf
      If lpUrlComponents\lpszExtraInfo And lpUrlComponents\dwExtraInfoLength
        sQuery$ = PeekS(lpUrlComponents\lpszExtraInfo, lpUrlComponents\dwExtraInfoLength, #PB_Unicode)
      EndIf
      
      If sDomain$ And sPath$
        If Not hSession
          hSession = WinHttpOpen(UserAgent$, #WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, #WINHTTP_NO_PROXY_NAME, #WINHTTP_NO_PROXY_BYPASS, 0)
        EndIf
        If hSession
          hInternet = WinHttpConnect(hSession, sDomain$, lPort, #Null)
          If hInternet
            hRequest = WinHttpOpenRequest(hInternet, RequestType$, sPath$+sQuery$, #Null, #WINHTTP_NO_REFERER, #WINHTTP_DEFAULT_ACCEPT_TYPES, lFlags)
            If hRequest
              If StringByteLength(OptionalData$, #PB_UTF8)
                *OptionalBuffer = AllocateMemory(StringByteLength(OptionalData$, #PB_UTF8)+1)
              EndIf
              If *OptionalBuffer
                OptionalLength = MemorySize(*OptionalBuffer)
                PokeS(*OptionalBuffer, OptionalData$, OptionalLength, #PB_UTF8)
                OptionalLength - 1
              EndIf
              If lpUrlComponents\nScheme = #INTERNET_SCHEME_HTTP
                WinHttpSetOption(hRequest, #WINHTTP_OPTION_REDIRECT_POLICY, @lRedirectPolicy, SizeOf(Long))
              EndIf
              If Len(Username$)
                WinHttpSetCredentials(hRequest, #WINHTTP_AUTH_TARGET_SERVER, #WINHTTP_AUTH_SCHEME_BASIC, Username$, Password$, #Null)
              EndIf
              If WinHttpAddRequestHeaders(hRequest, "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"+#CRLF$, -1, #WINHTTP_ADDREQ_FLAG_ADD)
                WinHttpAddRequestHeaders(hRequest, "Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7"+#CRLF$, -1, #WINHTTP_ADDREQ_FLAG_ADD)
                WinHttpAddRequestHeaders(hRequest, "Accept-Language: en-us,en-gb;q=0.9,en;q=0.8,*;q=0.7"+#CRLF$, -1, #WINHTTP_ADDREQ_FLAG_ADD)
              EndIf
              If RequestType$ = "POST"
                WinHttpAddRequestHeaders(hRequest, "Content-Type: application/x-www-form-urlencoded"+#CRLF$, -1, #WINHTTP_ADDREQ_FLAG_ADD)
              EndIf
              If CallbackStart
                CallbackStart(CallbackID, hRequest)
              EndIf
              If WinHttpSendRequest(hRequest, HeaderData$, Len(HeaderData$), *OptionalBuffer, OptionalLength, OptionalLength, CallbackID)
                If WinHttpReceiveResponse(hRequest, #Null)
                  If WinHttpQueryHeaders(hRequest, #WINHTTP_QUERY_FLAG_NUMBER | #WINHTTP_QUERY_STATUS_CODE, #WINHTTP_HEADER_NAME_BY_INDEX, @lStatusCode, @lLongSize, #WINHTTP_NO_HEADER_INDEX)
                    If lStatusCode = 200
                      lResult = WinHttpQueryDataAvailable(hRequest, @lContentLen)
                    Else
                      lResult = #True
                      lContentLen = 0
                    EndIf
                    If lResult
                      *MemoryBuffer = AllocateMemory(16384)
                      If *MemoryBuffer
                        MemoryLength = MemorySize(*MemoryBuffer)-2
                        If ReturnHeader
                          If WinHttpQueryHeaders(hRequest, #WINHTTP_QUERY_RAW_HEADERS_CRLF, #WINHTTP_HEADER_NAME_BY_INDEX, *MemoryBuffer, @MemoryLength, #WINHTTP_NO_HEADER_INDEX)
                            lRetVal = ReAllocateMemory(*MemoryBuffer, MemoryLength)
                          EndIf
                        ElseIf lContentLen
                          Repeat
                            If MemoryLength-lReadUntilNow <= lContentLen
                              *MemoryBuffer = ReAllocateMemory(*MemoryBuffer, MemoryLength+lContentLen+1)
                              If *MemoryBuffer
                                MemoryLength = MemorySize(*MemoryBuffer)
                              Else
                                Break
                              EndIf
                            EndIf
                            If WinHttpReadData(hRequest, *MemoryBuffer+lReadUntilNow, lContentLen, @lBytesRead)
                              If lBytesRead
                                lReadUntilNow + lBytesRead
                              Else
                                Break
                              EndIf
                              If CallbackProgress
                                CallbackProgress(CallbackID, lReadUntilNow, lContentLen, (ElapsedMilliseconds() - lStartTime) / 1000)
                              EndIf
                            Else
                              Break
                            EndIf
                            If Not WinHttpQueryDataAvailable(hRequest, @lContentLen)
                              Break
                            EndIf
                          ForEver
                          If lReadUntilNow >= lContentLen
                            lRetVal = ReAllocateMemory(*MemoryBuffer, lReadUntilNow)
                          EndIf
                        EndIf
                      EndIf
                    EndIf
                  EndIf
                EndIf
              EndIf
              If *OptionalBuffer
                FreeMemory(*OptionalBuffer)
              EndIf
              If CallbackEnd
                CallbackEnd(CallbackID, lRetVal, lReadUntilNow, lContentLen, (ElapsedMilliseconds() - lStartTime) / 1000)
              EndIf
            EndIf
          EndIf
        EndIf
      EndIf
    EndIf
  EndIf
  
  If hRequest
    WinHttpCloseHandle(hRequest)
  EndIf
  If hInternet
    WinHttpCloseHandle(hInternet)
  EndIf
  ; If hSession
  ;   WinHttpCloseHandle(hSession)
  ; EndIf
  
  ProcedureReturn lRetVal
EndProcedure

Procedure.s ReceiveHTTPString(URL$, RequestType$ = "GET", ReturnHeader = #False, Username$ = "", Password$ = "", HeaderData$ = "", OptionalData$ = "", UserAgent$ = "WinHTTP - PureBasic", CallbackID = 0, CallbackStart.ReceiveHTTPStart = 0, CallbackProgress.ReceiveHTTPProgress = 0, CallbackEnd.ReceiveHTTPEnd = 0)
  Protected Result$, *MemoryBuffer
  *MemoryBuffer = ReceiveHTTPMemory(URL$, RequestType$, ReturnHeader, Username$, Password$, HeaderData$, OptionalData$, UserAgent$, CallbackID, CallbackStart.ReceiveHTTPStart, CallbackProgress.ReceiveHTTPProgress, CallbackEnd.ReceiveHTTPEnd)
  If *MemoryBuffer
    If ReturnHeader
      Result$ = PeekS(*MemoryBuffer, MemorySize(*MemoryBuffer), #PB_Unicode)
    Else
      Result$ = PeekS(*MemoryBuffer, MemorySize(*MemoryBuffer), #PB_UTF8)
    EndIf
    FreeMemory(*MemoryBuffer)
  EndIf
  ProcedureReturn Result$
EndProcedure

Procedure ReceiveHTTPFileEx(URL$, Filename$, RequestType$ = "GET", Username$ = "", Password$ = "", HeaderData$ = "", OptionalData$ = "", UserAgent$ = "WinHTTP - PureBasic", CallbackID = 0, CallbackStart.ReceiveHTTPStart = 0, CallbackProgress.ReceiveHTTPProgress = 0, CallbackEnd.ReceiveHTTPEnd = 0)
  Protected File, *MemoryBuffer
  *MemoryBuffer = ReceiveHTTPMemory(URL$, RequestType$, #False, Username$, Password$, HeaderData$, OptionalData$, UserAgent$, CallbackID, CallbackStart.ReceiveHTTPStart, CallbackProgress.ReceiveHTTPProgress, CallbackEnd.ReceiveHTTPEnd)
  If *MemoryBuffer
    File = CreateFile(#PB_Any, Filename$)
    If File
      WriteData(File, *MemoryBuffer, MemorySize(*MemoryBuffer))
      CloseFile(File)
      FreeMemory(*MemoryBuffer)
      ProcedureReturn #True
    EndIf
    FreeMemory(*MemoryBuffer)
  EndIf
  ProcedureReturn #False
EndProcedure
; IDE Options = PureBasic 5.31 (Windows - x86)
; CursorPosition = 46
; Folding = 5
; EnableThread
; EnableXP
; EnableAdmin