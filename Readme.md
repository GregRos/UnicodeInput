# Command Keyboard
This is a small application that lets you insert mathematical characters into ordinary text using special commands.

For example, the command `integral.2` is mapped to `∬`, a double integral. Other examples include;

* `integral.closed.2 ==> ∯`
* `set.in ==> ∈`
* `set.sub ==> ⊂`

You can change the command bindings to type any unicode character you desire.

Unicode contains 55,181 characters in the Basic Multilingual Plane alone. The vast majority of these characters can be used in most modern applications. Web browsers in particular can display almost all of them.

Although the majority of these characters belong to a particular language or writing system, and can be outputted by using the keyboard layout for the language, many others are more technical and despite wide-range support, are only used in a handful applications.

Unicode Commander puts many of those characters at your fingertips using a clear, intuitive syntax that doesn't disrupt normal typing. It is not a keyboard layout; instead, it is a system of macros that lets you map a command to a character. It is a bit similar to LaTeX, but is much simpler (and far less powerful) and can be used anywhere.

## Usage

You begin a unicode command by typing ` `` `  (two backticks), which is translated to the special symbol `ℳ:`. 

Then you type a command, which is a sequence of words separated by dots `.`. You terminate the command by pressing space, and the command is replaced by the appropriate character. For example:

`integral.closed.2` is replaced by ∬ (double integral).

Note that each word can contain almost any character. Other commands can be:

* `arrow.=>` becomes ⇒
* `braces.floor[` becomes ⌊

Typing causes a tooltip to appear that displays a list of possible commands you can type, so you don't need to look at a reference every time you want to type a particular symbol. 

## Customization
The mappings used by the program are taken from a `Layout.json` file, which maps every command (in its full form, e.g. `integral.2`) to a symbol. The file is user-editable, and you can add your own mappings freely.


