 
; ================================================================
; Contains utility commonly used utility functions.
; Meant to be reusable.
; ================================================================
#SingleInstance, Force
#include FancyEx.ahk

class _ahkUtilsHelper {

	IndexOf(arr, what) {
		for ix, value in arr
		{
			if(what = value) 
			{
				return ix
			}
		}
		return 0	
	}
	
	StringRepeat(what, count) {
		result := ""
		Loop, % count
		{
			result.= what
		}
		return result
	}
	
	static _builtInNames:=["_NewEnum", "methods", "HasKey", "_ahkUtilsDisableVerification", "Clone", "GetAddress", "SetCapacity", "GetCapacity", "MinIndex", "MaxIndex", "Length", "Delete", "Push", "Pop", "InsertAt", "RemoveAt", "base", "__Set", "__Get", "__Call", "__New", "__Init", "_ahkUtilsIsInitialized"]
	
	IsMemberBuiltIn(member) {
		return this.IndexOf(this._builtInNames, member) > 0
	}
	
	StringJoin(what, sep="") {
		res:=""
		for ix, value in what
		{
			if (A_Index != 1) 
			{
				res.=sep
			}
			res.=value
		}
		return res
	}
}

; Base class that provides member name verification services.
; Basically, inherit from this if you want your class to only have declared members (methods, properties, and fields assigned in the initializer), so that unrecognized keys will result in an error.
; The class implements __Get, __Call, and __Set.
class DeclaredMembersOnly {
	__Call(name, params*) {
		if (!_ahkUtilsHelper.IsMemberBuiltIn(name) && !this._ahkUtilsDisableVerification) {
			FancyEx.Throw("Tried to call undeclared method '" name "'.")
		}
	}

	__New() {
	
	}
	
	__Init() {
		; We want to disable name verification to allow the extending object's initializer to safely initialize the type's fields.
		if (this._ahkUtilsDisableVerification) {
			return
		}
		this._ahkUtilsDisableVerification := true
		this.methods := { }
		
		this.__Init()
		this.Delete("_ahkUtilsDisableVerification")
	}

	__Get(name) {
		if (!_ahkUtilsHelper.IsMemberBuiltIn(name) && !this._ahkUtilsDisableVerification) {
			FancyEx.Throw("Tried to get the value of undeclared member '" name "'.")
		}
	}
	
	__Set(name, values*) {
		if (!_ahkUtilsHelper.IsMemberBuiltIn(name) && !this._ahkUtilsDisableVerification) {
			FancyEx.Throw("Tried to set the value of undeclared member '" name "'.")
		}
	}

	__DisableVerification() {
		ObjRawSet(this, "_ahkUtilsDisableVerification", true)
	}
	
	__EnableVerification() {
		this.Delete("_ahkUtilsDisableVerification")
	}
	
	__IsVerifying[] {
		get {
			return !this.HasKey("_ahkUtilsDisableVerification")
		}
	}
	
	__RawGet(name) {
		this.__DisableVerification()
		value := this[name]
		this.__EnableVerification()
		return value
	}

}

; A 'namespace'-type class containing all the utility functions.
class Utils extends DeclaredMembersOnly {
	; 
	class Lang extends DeclaredMembersOnly  {
		DoesVarExist(ByRef var) {
		   return &var = &something ? 0 : var = "" ? 2 : 1 
		}
	}
	
	class System extends DeclaredMembersOnly {
		; Returns true if the mouse cursor is visible in the active window (used for games).
		; May not work correctly in all games.
		IsMouseCursorVisible() {
			StructSize := A_PtrSize + 16
			VarSetCapacity(InfoStruct, StructSize)
			NumPut(StructSize, InfoStruct)
			DllCall("GetCursorInfo", UInt, &InfoStruct)
			Result := NumGet(InfoStruct, 8)
			return Result > 1
		}
		
		; Returns a ProcessView object that allows read-only inspection of the process and its memory.
		; title - The title of the window for which to generate the view, or another suitable identifier (as WinExist)
		OpenProcessView(title) {
			return new this.ProcessView(title)
		}
		
		GetCurrentProcessId() {
			return DllCall("GetCurrentProcessId")	
		}

		; Provides read-only access to a process and its memory, can generate references to memory locations owned by the process.
		class ProcessView extends DeclaredMembersOnly {
			WindowTitle:="Uninit"
			ProcessHandle:=0
			Privilege:=0x1F0FFF
			
			; Private
			_getBaseAddress(hWnd) {
				return DllCall( A_PtrSize = 4
										? "GetWindowLong"
										: "GetWindowLongPtr"
									, "Ptr", hWnd
									, "Int", -6
									, "Int64") ; Use Int64 to prevent negative overflow when AHK is 32 bit and target process is 64bit
				 ; If DLL call fails, returned value will = 0
			}
			
			WindowHandle[] {
				get {
					WinGet, hwnd, ID, % this.WindowTitle
					return hwnd
				}
			}
			
			BaseAddress[] {
				get {
					return this._getBaseAddress(this.WindowHandle)
				}
			}
			
			ProcessId[] {
				get {
					WinGet, pid, PID, %windowTitle%
					return pid
				}
			}
			
			__New(windowTitle) {
				this.WindowTitle := windowTitle
			}
			
			; Reads from a memory location owned by the process.
			; addr - An absolute address of the memory location to read.
			; datatype - The datatype. Use int/uint for bytes.
			; length - the number of bytes to be read from the location.
			Read(addr, datatype="int", length=4) {
				
				prcHandle := DllCall("OpenProcess", "Ptr", this.Privilege, "int", 0, "int", this.ProcessId)
				VarSetCapacity(readvalue,length, 0)
				DllCall("ReadProcessMemory","Ptr",prcHandle,"Ptr",addr,"Str",readvalue,"Uint",length,"Ptr *",0)
				finalvalue := NumGet(readvalue,0,datatype)
				DllCall("CloseHandle", "Ptr", prcHandle)
				if (finalvalue = 0 && A_LastError != 0) {
					format = %A_FormatInteger% 
					SetFormat, Integer, Hex 
					addr:=addr . ""
					msg=Tried to read memory at address '%addr%', but ReadProcessMemory failed. Last error: %A_LastError%. 
					
					FancyEx.Throw(msg)
				}
				return finalvalue
			}
			
			; Reads from a memory location owned by the process, 
			; the memory location being determined from a nested base pointer, and a list of offsets.
			; address - the absolute address to read.
			ReadPointer(address, datatype, length, offsets) {
				B_FormatInteger := A_FormatInteger 
				for ix, offset in offsets
				{
					baseresult := this.Read(address, "Ptr", 8)
					Offset := offset
					SetFormat, integer, h
					address := baseresult + Offset
					SetFormat, integer, d
				}
				SetFormat, Integer, %B_FormatInteger%
				return this.Read(address,datatype,length)
			}
			
			; Same as ReadPointer, except that the first parameter is an *offset* starting from the base address of the active window of the process.
			ReadPointerByOffset(baseOffset, datatype, length, offsets) {
				return this.ReadPointer(this.BaseAddress + baseOffset, datatype, length, offsets)
			}
			
			; Returns a self-contained ProcessVariableReference that allows reading from the specified memory location (as ReadPointer).
			GetReference(baseOffsets, offsets, dataType, length, label := "") {
				return new this.ProcessVariableReference(this, baseOffsets, offsets, dataType, length, label) 				
			}	
			
			; Closes the ProcessView. Further operations are undefined.
			Close() {
				r := DllCall("CloseHandle", "Ptr", hwnd)
				this.ProcessHandle := 0
			}
			
			; Self-contained class for viewing a memory location owned by the process.
			class ProcessVariableReference extends DeclaredMembersOnly  {
				Process:="Uninit"
				BaseOffset:="Uninit"
				Offsets:="Uninit"
				DataType:="Uninit"
				Length:="Uninit"
				Label:="Uninit"
				
				__New(process, baseOffset, offsets, dataType, length, label := "") {
					this.Process:=Process
					this.BaseOffset:=baseOffset
					this.Offsets:=offsets
					this.DataType:=dataType
					this.Length:=length
					this.Label := label
				}
				
				Value[] {
					get {
						return this.Process.ReadPointerByOffset(this.BaseOffset, this.DataType, this.Length, this.Offsets)
					}
				}	
			}
		}
	}
	
	class Hotkey extends DeclaredMembersOnly 
	{
		HotkeyName(hotkeyName := "") 
		{
			hotkeyName := hotkeyName == "" ? A_ThisHotkey : hotkeyName
			RegExMatch(A_ThisHotKey, "([$*+~^!#<>?]*)(.+)", hotkey)
			if (InStr(hotkey1, "+") && StrLen(hotkey2) = 1)
			{
				if hotkey is lower
				{
					StringUpper, hotkey2, hotkey2
				}
			}
			return hotkey2
		}
		
		RegisterUpDown(hk,downHandler, upHandler = "", options = "") {
			if (hk = "None") {
				return
			}
			this.Register(hk, downHandler, options)
			if (upHandler) {
				this.Register(hk " up", upHandler, options)
			}
		}
		
		Register(hk, handler, options = "") {
			if (hk = "None") {
				return
			}
			try {
				Hotkey, %hk%, %handler%, %options%
			} catch ex {
				FancyEx.Throw("Failed to register hotkey", ex)
			}
		}
		
		RegisterAlias(hotkey, target, wheelDuration = 35) {
			if (hk = "None") {
				return
			}			
			
			if (hotkey = "WheelUp" || hotkey = "WheelDown") {
				Utils.Hotkey.Register(hotkey, Utils.Send.HoldDown.Bind(Utils.Send, target, wheelDuration))
				return
			}
			method := Utils.Send.SendInput
			Utils.Hotkey.RegisterUpDown(hotkey, method.Bind(Utils.Send, "{" target " down}"), method.Bind(Utils.Send, "{" target " up}"))
		}
		
		static _monitoredKeyTable:=""
		
		_recordTime(name) {
			this._monitoredKeyTable[name] := A_TickCount
		}
		
		RecordTickCount(hotkey, name, options := "") {
			this._monitoredKeyTable[name] := hotkey
			this.Register(hotkey, this._recordTime.Bind(this, name), options) 
		}
		
		GetRecordedTickCount(name) {
			return this._monitoredKeyTable[name]
		}
	}
	
	class Send extends DeclaredMembersOnly {
		
		SendInput(input) {
			SendInput, % input
		}
	
		; Sends a raw input string through copy-paste functionality, rather than the keyboard. 
		; This is required for some kinds of sequences.
		; This is achieved by using the Clipboard and sending Ctrl+V.
		CopyPaste(input)
		{
			tmp:=ClipboardAll
			Clipboard:=input
			ClipWait
			SendInput, ^v
			Sleep 50
			Clipboard:=tmp
			return
		}
		
		; Holds down the key 'key' for 'ms' milliseconds. This is a string which is passed to SendInput, so use key names for things like Space.
		; If ms = -1 (default), the 'up' command isn't transmited (the key is never released).
		HoldDown(key, ms = -1)
		{
			if (key = "WheelDown" || key = "WheelUp") {
				SendInput, {%key%}
				return
			}
			SendInput, {%key% down}
			if (ms != -1) {
				Sleep, % ms
				SendInput, {%key% up}
			}
		}
			
	
			
		; Holds down the list object 'keys' for a period of 'ms' milliseconds.
		HoldDownMany(keys, ms = -1) 
		{
			if (!IsObject(keys)) {
				keys:=Utils.String.ToList(keys)
			}
			for ix, key in keys 
			{
				SendInput, {%key% down}
			}
			if (ms != -1) {
				Sleep, % ms
				for ix, key in keys
				{
					SendInput, {%key% up}
				}
			}
		}
		
		HoldDownRepeat(key, count, holdDown, betweenPresses) {
			Loop, % count
			{
				Utils.Send.HoldDown(key, holdDown)
				Sleep, % betweenPresses
			}
		}
		
		StopHolding(key) {
			if (GetKeyState(key, "T")) {
				SendInput, {%key% up}
			}
		}
	}

	class Array extends DeclaredMembersOnly {
		; Returns an array consisting of 'item' 'count' times.
		Replicate(item, count)
		{
			arr:=[]
			Loop, %count%
			{
				arr.Insert(item)
			}
			return arr
		}
		
		Length(arr) 
		{
			len:=arr.Length()
			if (len <> 0)
			{
				return len
			}
			len := 0
			for ix, item in arr
			{
				len := len + 1
			}
			return len
		}
		
		; Returns the index at which 'what' appears in the array 'arr', or 0 if no such item was found.
		IndexOf(arr, what) {
			return _ahkUtilsHelper.IndexOf(arr, what)
		}

		; Sorts the array using the specified options. 
		; The options are of the same type as passed to the Sort built-in function.
		Sort(what, options="N D,") {
			str:=Utils.String.Join(what, ",")
			Sort, str, %options%
			arr:=[]
			Loop, Parse, str, `,
			{
				arr.Insert(A_LoopField)
			}
			return arr
		}
		
		; Concatenates two non-associative arrays.
		Concat(a, b)
		{
			c := []
			for x, y in a 
				c.Insert(y)
			for x, y in b
				c.Insert(y)
			return c
		}
		
		Subsequence(arr, firstIndex = "start", lastIndex = "end") {
			result:=[]
			firstIndex:=firstIndex != "start" ? firstIndex : arr.MinIndex()
			lastIndex:=lastIndex != "end" ? lastIndex : arr.MaxIndex()
			if (lastIndex < firstIndex) {
				return result
			}
			Loop, % lastIndex - firstIndex + 1
			{
				result.Insert(arr[firstIndex + A_Index - 1])
			}
			return result
		}
		
		Map(arr, projection) {
			result:=[]
			for index, key in arr
			{
				result.Insert(projection.Call(index, key))
			}
			return result
		}
		
		Take(arr, n)
		{
			newArr := []
			i := 0
			for ix, item in arr
			{
				if (i == n) break
				newArr.Insert(item)
				i := i + 1
			}
			return newArr
		}
		
		Filter(arr, filter) {
			result:=[]
			for index, key in arr
			{
				if (filter.Call(index, key)) {
					result.Insert(key)
				}
			}
			return result
		}
	}

	class String extends DeclaredMembersOnly {
		PadRight(str, toWidth, char := " ")
		{
			myLen := StrLen(str)
			extras := toWidth - myLen
			if (extras <= 0) return str
			padding := Utils.String.Repeat(char, extras)
			result := str padding
			return result
		}
		
		PadLeft(str, toWidth, char := " ")
		{
			myLen := StrLen(str)
			extras := toWidth - myLen
			if (extras <= 0) return str
			padding := Utils.String.Repeat(char, extras)
			result := padding str 
			return result
		}		
		
		ToList(str) {
			list:=[]
			Loop, Parse, str
			{
				list.Insert(A_LoopField)
			}
			return list
		}
		
		
		StartsWith(where, what, caseSensitive) 
		{
			if (what == "") 
			{
				return true
			}
			len := StrLen(what)
			initial := SubStr(where, 1, len)
			return caseSensitive ? initial == what : initial = what
		}
	
		; Similar to String.Format in C#. Numeric tokens, written [n], are replaced by the array 'data'
		; With [index] being replaced by data[index]. data can also not be an array, in which case it is used as [1].
		; Tokens of the form [!name] are replaced by the interpolated contents of the global variable 'name'.
		; In order to remove a source for bugs, if the variable doesn't exist, the token is replaced with an error message.
		; The [ character can be escaped using [[. The ] character doesn't need to be escaped.
		Format(format, data)
		{
			global
			if (data.MaxIndex() = "") 
			{
				data:=[data]
			}
			local res:=format
			for index, value in data
			{
				res:=RegExReplace(res, "(?<!\[)\[" index "\]", value)
				format:=res
			}
			local matches:=Utils.Regex.MultiMatchGroups(format, "(?<!\[)\[!(\w+)\]")
			format:=res
			for index, match in matches
			{
				local varName:=match.groups[1]
				local text:=match.text
				if (Utils.Lang.DoesVarExist(%varName%) = 1) 
				{
					local value:=%varName%
					StringReplace, res, format, %text%, %value%, All
					format:=res
				}
				else
				{
					StringReplace, res, format, %text%, [!%varName% doesn't exist], All
					format:=res
				}
			}
			StringReplace, res, format, [[, [, All
			return res
		}
		
		Contains(where, what)
		{
			return
		}
		
		; Joins an array of strings into a single string, placing a separator between them.
		Join(what, sep="") 
		{
			return _ahkUtilsHelper.StringJoin(what, sep)
		}	
		
		Repeat(what, count) 
		{
			return _ahkUtilsHelper.StringRepeat(what, count)
		}
		
		Split(what, delims = "", omits = "") 
		{
			return StrSplit(what, delims, omits)
		}
	}

	class Regex extends DeclaredMembersOnly {
		; Matches the specified regex as many times as possible, returning an array of {text:string (full match), groups:[string] (submatches)}
		; Named match groups aren't supported, though.
		MultiMatchGroups(haystack, needle)
		{
			array:=[]
			Loop, 10
			{
				match%A_Index%:=[""]
			}
			while (pos := RegExMatch(haystack, needle, match, ((pos>=1) ? pos : 1)+StrLen(match)))
			{
				lastIndex:=10
				curArray:=[]
				Loop, 10
				{
					cur:=match%A_Index%
					if (cur.MaxIndex() = 1) 
					{
						break
					}
					curArray.Insert(cur)
				}
				array.Insert({text:match, groups:curArray})
			}
			Return array
		}

		; Matches the speicfic regex 
		MultiMatch(haystack, needle)
		{
		   array:=[]
		   while (pos := RegExMatch(haystack, needle, match, ((pos>=1) ? pos : 1)+StrLen(match)))
			  array[A_Index]:=match
		   Return array
		}
	}
}