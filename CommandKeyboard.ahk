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

SendMode, Input
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
    ,"!Tab","Escape","LWin","RWin",
    ,"AppsKey", "LButton"
    , "RButton"]

global keyAutoCompleteKey := "Tab"

NodeToString(namespace, keyword)
{
    if (namespace == "")
    {
        return keyword
    }
    else
    {
        parString := NodeToString(namespace.Parent, namespace.Keyword)
        return parString <> "" ? parString "." keyword : keyword
    }
}

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
                return NodeToString(this.Parent, this.Keyword)
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

ReplaceLastCharactersWith(typedLength, replacement) 
{
    ; I've found this implementation to be a lot better than {backspace n}. This way
    ; makes a single modification to the text, instead of multiple modifications. Some
    ; programs take time to register each modification.
    
    ; However, it does require modern caret controls.
    Send, {Shift down}{Left %typedLength%}{Shift up}
    if (typedLength == 0) 
    {
        return
    }
    else if (replacement == "") 
    {
        Send, {backspace}
    }
    else 
    {
        Send, % replacement
    }
}

ReplaceCommandString(replacement)
{
    str := NodeToString(nodeNamespace, strCurrentKeyword)
    totalLen := StrLen(str)
    ReplaceLastCharactersWith(totalLen, replacement)
}

ExecuteCurrentCommand() 
{
    selected := nodeNamespace.FindNode(RTrim(strCurrentKeyword, "."))
    ExecuteCommand(selected)
}

; Called when the command terminator is used to resolve a command.
ExecuteCommand(node) 
{
    result := node.Value
    ReplaceCommandString(result)
    if (result == "")
    {
        ErrorTooltip("Not found: " strNamespace)
    }
    else
    {
        RemoveTooltip()
    }
    ExitCommandMode()
}

; Enter command mode.
InputCommand() 
{
    DisplayInfo()
    isInCommandMode := true    
}

CannotErase() 
{
    ; An empty function that gets called when attempting to backspace
    ; something that should not be erased.
}

; When a key is pressed in command mode, this will parse its affect on
; the selected command.
ParseCommandKey() 
{
    strCurrentKeyword := strCurrentKeyword Utils.Hotkey.HotkeyName()
    DisplayInfo()
}

; Get the completions of the current command.
GetEligibleCommands() 
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
        data.Insert(node)
    }
    return data
}

AutoComplete() 
{
    eligible := GetEligibleCommands()
    fst := eligible[1]
    if (fst.Value != "") 
    {
        ExecuteCommand(fst)
    }
    else
    {
        strCurrentKeyword := fst.Value
    }
}


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

; Displays the tooltip
DisplayInfo() 
{
    data := []
    results := GetEligibleCommands()
    for n, node in results
    {
        key := node.ToString
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
        hasValue := nodeNamespace.Value <> "" ? ">" : ""
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

; These are needed to register the predicates for use in the
; dynamic Hotkey command.
#if isInCommandMode && (StrLen(strCurrentKeyword) == 0 && !nodeNamespace.Parent)
#if isInCommandMode && (StrLen(strCurrentKeyword) > 0 || nodeNamespace.Parent)

#if 

; Execute command on Space.
Hotkey, Space, ExecuteCurrentCommand
; Execute command on Enter.
Hotkey, Enter, ExecuteCurrentCommand

; Terminate the current keyword and also type a . 
Hotkey, ~., TerminateKeyword

; If we're in command mode and there is a command char to erase, erase the command char
; and also emit the original backspace.
Hotkey, If, isInCommandMode && (StrLen(strCurrentKeyword) > 0 || nodeNamespace.Parent)
Hotkey, ~Backspace, EraseCommandCharacter

; If we're in command mode but there is no command char to erase, then backspace
; is a noop.
Hotkey, If, isInCommandMode && (StrLen(strCurrentKeyword) == 0 && !nodeNamespace.Parent)
Hotkey, Backspace, CannotErase
Hotkey, If

;==============================================
;Active hotstring definition
;---------------------------------------------
#if !isInCommandMode
!`::
    InputCommand()
    return
#if
#if isInCommandMode
Tab::
    AutoComplete()
#if


