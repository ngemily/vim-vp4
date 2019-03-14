## Intro

vp4 does the following:

- Interact with perforce _without leaving Vim_
- _Automatically_ **open files** for edit
- Ridiculously functional **annotation** by adding the _date_, _user_, and
  _changelist_ _description_ for each chunk of code
- Fantastical **diffing**, including vs _depot_, vs _shelved_, vs _previous_ rev
- **File history** browsing; Make Vim _a Perforce time machine_
- **Depot browsing** with sync support

## Install

### Via plugin manager [vim-plug](https://github.com/junegunn/vim-plug) 
_recommended_

If using vim-plug (recommended), add the following to the list of plugins in
your vimrc:

```
Plug 'ngemily/vim-vp4'
```

### Manual

Download, unzip, and copy into `~/.vim` as following:

```
cp autoload/vp4.vim ~/.vim/autoload/
cp doc/vp4.txt ~/.vim/doc/
cp plugin/vp4.vim ~/.vim/plugin/
```

Generate helptags by running the following in vim:

```
:helptags ~/.vim/doc
```

## Commands

### Analysis

_These commands query and display information about a file._

`:[range]Vp4Annotate`

Opens a scrollbound split showing the changelist where each line was last
modified, and the date, user, and description of the changelist.  This feature
is slow on large files with many different last changes.  To speed it up,
visually select lines to fully annotate (recommended), or use
|g:vp4_annotate_simple| to show only the changelist number.  `q` exits.

Opens a view like

```
    +----------------------------------+------------------------+
    | <Description> <date> <user> <cl> | for (auto elem : l) {  |
    | <Description> <date> <user> <cl> |     std::cout << elem; |
    |                ...               |          ...           |
    +----------------------------------+------------------------+
    | :Vp4Annotate                                              |
    +----------------------------------+------------------------+
```

_Note: Annotations will be misaligned on files that are currently being edited.
This is because `p4 annotate` works only submitted revisions of files.  To
workaround this, it is suggested to open the last submitted revision of the
filelog using `:Vp4Filelog` and run `:Vp4Annotate` on that._

`:Vp4Diff [s][p][@{cl}][#{rev}]`

With no arguments, the depot version of the current file in a vertical split,
in diff mode.  Hit `q` to exit.

- With `[s]` diff with shelved in current changelist.  Only available if file is
  open for edit and shelved.
- With `[p]` diff with previous version.  Available on any file that exists in
  the depot.
- With `[@{cl}]` diff with shelved in changelist `{cl}`.  Available on any file
  that exists in the depot, provided it is actually shelved in changelist.
- With `[#{rev}]` diff with revision `{rev}`.

`:Vp4Filelog`

Populate the quick-fix or location list with the past revisions of this file.
The file is not actually retrieved from the server until it is opened.  Lists
in chronologically reverse order.

Unset `g:vp4_open_loclist` to prevent the location list from being opened
automatically.  Set `g:vp4_filelog_max` to limit the number of revisions
listed.

### Change specification

_These commands perform actions on changelists._

`:Vp4Change`

Opens the change specification in a new split.  Equivalent to `p4 change -o`
if current file is not already opened in a changelist and `p4 change -o -c
{cl}` if already opened in a changelist.  Use the write `:w` command to make
the change, quit `:q` to abort.

`:Vp4Describe`

Opens a preview window containing a description of the changelist in which the
current file is open, obtained from `p4 describe <cl>`

`:Vp4Shelve[!]`

Calls the shelve command for the current file, for the changelist in which it
is currently open.  Not available unless the file is open in a named
changelist (i.e. not the default changelist).  With `[!]` performs the command
with `-f`, overwriting any existing shelved version.

### File editing

_These commands perform actions on files that alter their state in Perforce._

`:Vp4Add`

Opens current file for add.

`:Vp4Delete[!]`

Opens current file for delete.  Unloads current buffer.  Confirms before doing
so; use [!] to skip confirmation.

`:Vp4Edit`

Opens current file for edit.

`:Vp4Reopen`

Move the current file to a different changelist.  Lists all open changelists
and prompts for a selection.

`:Vp4Revert[!]`

Reverts current file.  Confirms before doing so.  Use `[!]` to skip
confirmation.

## Passive Features

### Prompt for edit

When writing a file, set `g:vp4_prompt_on_write` to enable prompt on write to
`p4 edit` the file.

### Open depot file

Set `g:vp4_allow_open_depot_file` to allow vim to be invoked on a depot path
specification, like `vim //main/foo/bar/baz.cpp` where:

- if the file has been synced into the workspace, open the local file
- otherwise, fetch the file contents from server

## Credits

This plugin was heavily inspired by vim-fugitive.  Additionally, the author
was helped greatly by the book Learn Vimscript the Hard Way and Vim's
excellent built-in documentation.
