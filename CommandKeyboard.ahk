#SingleInstance Force

_Version=0.8.0
#include <JSON>
#include <_Struct>
#include <sizeof>
#include <TT>
#include <AhkUtility>

; Required definition for TT.ahk
Struct(Structure,pointer:=0,init:=0){
    return new _Struct(Structure,pointer,init)
} 

; ================================
; Settings and Strings
; ================================
global keyTerminateKeyword := "."
global strScriptMarker := "ℳ:"

; The offset between the location of the mouse cursor and where a tooltip appears
global intTooltipDriftX :=30
global intTooltipDriftY :=30
global intMaxTooltipLines := 20
; The time a certain kind of tooltip remains visible. Later modified by the length of the text.
; -1 means forever.

global intInfoTooltipTime := -1
global intErrorTooltipTime := 1000
global intWarningTooltipTime := -1

global strLastChar := ""


global strNamespace := ""
global strCurrentKeyword := ""

global strPartialKey := ""
global isInCommandMode := false
global arrKeyPrematureTerminators := ["F1"
    ,"F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"
    ,"Up","Down","Left","Right","PgDn","PgUp","End","Home","Insert","Delete"
    ,"Tab","!Tab","Escape","LWin","RWin",
    ,"AppsKey", "LButton"
    , "RButton"]
    

class LayoutTree
{
    class Node 
    {
        __New(keyword, value, parent, isValid := true) 
        {
            this.Value := value
            this.Keyword := keyword
            this.Parent := parent
            this.IsValid := isValid
            ; We use Scripting.dictionary because it is case sensitive, and layouts should be case sensitive (e.g. to tell gr.A and gr.a apart)
            this.Children := ComObjCreate("Scripting.dictionary")
        }
    
        FindNode(keyword) 
        {
            return this.Children.Exists(keyword) ? this.Children.item("" + keyword) : new LayoutTree.Node(keyword, "", this, false)
        }
        
        AddNode(keyword, value)
        {
            newNode := new LayoutTree.Node("" + keyword, value, this)
            this.Children.item(keyword) := newNode
            return newNode
        }
        
        TotalLength[] 
        {
            get 
            {
                return StrLen(this.ToString)
            }
        }
        
        ToString[] 
        {
            get
            {
                parString := this.Parent.ToString
                return parString <> "" ? parString "." this.Keyword : this.Keyword
            }
        }
    }
    
    __New() 
    {
        this.Root := new LayoutTree.Node("", "", "")
    }
    
    Register(key, value)
    {
        keys := Utils.String.Split(key, keyTerminateKeyword)
        cur := this.Root
        for index, key in keys 
        {
            next := cur.FindNode(key)
            if (!next.IsValid) {
                next := cur.AddNode(key, "")
            }
            cur := next
        }
        if (cur.Value <> "") 
        {
            FancyEx.Throw("Already bound: '" cur.Keyword "' = '" cur.Value "'")
        }
        cur.Value := value
        return cur
    }
    
    Match(key) 
    {
        keys := Utils.String.Split(key, keyTerminateKeyword)
        cur := this.Root
        for index, key in keys
        {
            cur := cur.FindNode(key)
            if (cur.Keyword == "") {
                return ""
            }
        }
        return cur
    }
    
    FromJson(jsonText)
    {
        tree := new LayoutTree()
        data:= JSON.Load(jsonText, 0)
        bindings := data.bindings
        for key, entry in bindings 
        {
            nodeKey := entry[1]
            nodeValue := entry[2]
            info := entry[3]

            if (InStr(info.flags, "skip1", true)) 
            {
                StringTrimLeft, nodeValue, nodeValue, 1
            }
            tree.Register(nodeKey, nodeValue)
        }
        return tree
    }
}

IfNotExist, Layout.json
{
    FileInstall, Layout.json, Layout.json
}

FileRead, jsonText, *P65001 Layout.json ;65001 is the UTF-8 codepage.    

global layout := LayoutTree.FromJson(jsonText)
jsonText := ""

global nodeNamespace := layout.Root
global arrNodeOptions := []
; Displays a tooltip with the settings used by this script.

; Logs the A_ThisHotKey. Calling when one of the monitored keys is pressed.

PopKeyword()
{
    strCurrentKeyword := nodeNamespace.Keyword
    nodeNamespace := nodeNamespace.Parent
}

EraseCommandCharacter() 
{
    if (StrLen(strCurrentKeyword) > 0) 
    {
        StringTrimRight, strCurrentKeyword, strCurrentKeyword, 1
    }
    else if (nodeNamespace.Parent) 
    {
        PopKeyword()
    }
    DisplayInfo()
    return
}

ExitCommandMode()
{
    isInCommandMode := false
    strCurrentKeyword := ""
    nodeNamespace := layout.Root
}

; Called when the user uses the keyboard or mouse to navigate away.
NavigatedAway() 
{
    ExitCommandMode()
    ErrorTooltip("Navigated away")
}

; Enter a deeper namespace.
CloseKeyword()
{
    nodeNamespace := nodeNamespace.FindNode(RTrim(strCurrentKeyword, "."))
    strCurrentKeyword := ""
}

; Called when the command separator is used to specify a longer namespace.
TerminateKeyword() 
{
    ParseCommandKey()
    CloseKeyword()
    DisplayInfo()
    return
}

; Called when the command terminator is used to resolve a command.
ExecuteCommand() 
{
    CloseKeyword()
    result := nodeNamespace.Value
    totalLen := nodeNamespace.TotalLength
    SendInput, {backspace %totalLen%}
    if (result == "")
    {
        ErrorTooltip("Not found: " strNamespace)
    }
    else
    {
        SendInput, % result
        RemoveTooltip()
    }
    ExitCommandMode()
}

InputCommand() 
{
    DisplayInfo()
    isInCommandMode := true    
}

CannotErase() 
{
    
}
    
ParseCommandKey() 
{
    strCurrentKeyword := strCurrentKeyword Utils.Hotkey.HotkeyName()
    DisplayInfo()
}



#if isInCommandMode
#if
Hotkey, If, isInCommandMode
Loop, % 127 - 33
{
    RealIndex := A_Index + 33
    c:=Chr(RealIndex)
    if (c != ".")
    {
        if c is upper 
            HotKey, ~+%c%, ParseCommandKey
        else 
            HotKey, ~%c%, ParseCommandKey
    }
}

for ix, key in arrKeyPrematureTerminators
{
    Hotkey, %key%, NavigatedAway
}
#if isInCommandMode && (StrLen(strCurrentKeyword) == 0 && !nodeNamespace.Parent)
#if isInCommandMode && (StrLen(strCurrentKeyword) > 0 || nodeNamespace.Parent)

#if 

Hotkey, $Space, ExecuteCommand
Hotkey, Enter, ExecuteCommand
Hotkey, ~., TerminateKeyword

Hotkey, If, isInCommandMode && (StrLen(strCurrentKeyword) > 0 || nodeNamespace.Parent)
Hotkey, ~Backspace, EraseCommandCharacter

Hotkey, If, isInCommandMode && (StrLen(strCurrentKeyword) == 0 && !nodeNamespace.Parent)
Hotkey, Backspace, CannotErase
Hotkey, If

;==============================================
;Tooltip Rendering Code
;---------------------------------------------

CoordMode, Caret, Screen
global myTip := TT("Icon=2 Theme NoFade", "", "Results")
myTip.Font("S11, Consolas")

myTip.Color("080E81", "F0F1FE")

InfoTooltip(text, title) 
{
    myTip.Title(title)
    myTip.Icon(1)
    MyTooltip(text, intInfoTooltipTime)
}

WarningTooltip(text) 
{
    myTip.Title("Warning")
    myTip.Icon(2)
    MyTooltip(text, intWarningTooltipTime)
}

ErrorTooltip(text)
{
    myTip.Title("Error")
    myTip.Icon(3)
    myTooltip(text, intErrorTooltipTime)
}

global strTooltipText := ""

MyTooltip(text, time) 
{
    factor := StrLen(text) / 15 ; So longer tooltips will display longer!
    time :=factor < 0 || time == -1? time : factor * time
    if (strTooltipText <> text)
    {
        myTip.Text(text)
        strTooltipText := text
    }
    myTip.Show("", A_CaretX + intTooltipDriftX, A_CaretY + intTooltipDriftY)
    if time != -1
        SetTimer, RemoveToolTip, %time%
    return

    RemoveToolTip:
    SetTimer, RemoveToolTip, Off
    myTip.Hide()
    return
}

RemoveTooltip() 
{
    myTip.Hide()
}

MakeTable(rows, spacings, maxRows)
{
    maxWidths := []
    for i, row in rows
    {
        for j, col in row
        {
            maxWidth := maxWidths[j]
            maxWidths[j] := maxWidth < StrLen(col) ? StrLen(col) : maxWidth
        }
    }
    
    for i, spacing in spacings
    {
        maxWidths[i] := maxWidths[i] + spacings[i]
    }
    
    maxWidths[maxWidths.MaxIndex()] := 0
    
    lines := []
    for i, row in rows
    {
        rowText := ""
        if (i > maxRows)
        {
            lines.Insert("...")
            break
        }
        for j, col in row
        {
            rowText .= Utils.String.PadRight(col, maxWidths[j])
        }
        lines.Insert(rowText)
    }
    text := Utils.String.Join(lines, "`r`n")
    return text
}

; Performs an Input call using the settings used in this script.

DisplayInfo() 
{
    data := []
    nsNode := nodeNamespace
    for key, node in nsNode.Children
    {
        node := nsNode.Children.item(key)
        if (!Utils.String.StartsWith(key, strCurrentKeyword, true))
        {
            continue
        }
        count := node.Children.Count()
        infoBox := ""
        infoBox .= count = 0 ? " " : "+"
        infoBox .= node.Value <> "" ? ">" : ""
        infoBox := (infoBox = "" ? " " : infoBox) "|"
        infoBox := Utils.String.PadLeft(infoBox, 3, " ")
        
        data.Insert([infoBox, key])
    }
    
    text := MakeTable(data, [3, 1], intMaxTooltipLines)
    if (text == "") 
    {
        text := "(No results)"
        WarningTooltip(text)
    } 
    else
    {
        hasValue := nsNode.Value <> "" ? ">" : ""
        title := hasValue nsNode.Keyword
        title := title == "" ? "Info" : title
        InfoTooltip(text, title)
    }
}


;==============================================
;Menu and GUI-related code
;---------------------------------------------
global IsAutoStart:=FileExist(AutoStartShortcutPath)
global AutoStartShortcutPath:=A_Startup "\Command Keyboard.lnk"
PrepareIcon() 
{
    IfExist, Images\icon.ico
    {
        Menu, Tray, Icon, Images\icon.ico, 1
    }
}
PrepareIcon()

PrepareTooltipMenu()
{
    global _version
    Menu, Tray, DeleteAll
    Menu, Tray, NoStandard
    Menu, Tray, Tip, Command Keyboard! v%_version%
    Menu, Tray, Add, Help!, HelpMe
    Menu, Tray, Add, View Mappings, Mappings 
    Menu, Tray, Add, Auto Start, ToggleAutoStart
    Menu, Tray, Add
    Menu, Tray, Standard
    
    if (IsAutoStart)
    {
        Menu, Tray, Check, Auto Start
    }
    return
    HelpMe:
        Run https://github.com/GregRos/CommandKeyboard
        return
    Mappings:
        Run https://raw.githubusercontent.com/GregRos/CommandKeyboard/master/Layout.json
        return
    ToggleAutoStart:
        if (IsAutoStart) 
        {
            FileDelete, %AutoStartShortcutPath%
            IsAutoStart=
        }
        else
        {
            FileCreateShortcut, %A_ScriptFullPath%, %AutoStartShortcutPath%, %A_ScriptDir%,  
            IsAutoStart=true
        }
        Menu, Tray, ToggleCheck, Auto Start
        return
}
PrepareTooltipMenu()

;==============================================
;Active hotstring definition
;---------------------------------------------
#if !isInCommandMode
:*?:````::
    InputCommand()
    return
#if

