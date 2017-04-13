---
layout: default
---

_Integration with Perforce.  Inspired by
[tpope/vim-fugitive](https://github.com/tpope/vim-fugitive)._

                                       ___
                                      //| |
                          ___   __ __//_| |_
                          \  \ // '_ \__  __|
                           \  V/| |_) ; | |
                            \_/ | .--'  |_|
                                | |
                                \_|


## Intro

vp4 does the following:

- Interact with perforce _without leaving Vim_
- _Automatically_ **open files** for edit
- Ridiculously functional **annotation** by adding the _date_, _user_, and
  _changelist_ _description_ for each chunk of code
- Fantastical **diffing**, including vs _depot_, vs _shelved_, vs _previous_ rev
- **File history** browsing; Make Vim _a Perforce time machine_

## Summary

- [Commands](#commands)
    - [Analysis](#analysis)
        - [Vp4Annotate]
        - [Vp4Diff]
        - [Vp4Filelog]
    - [Change specification](#change-specification)
        - [Vp4Change]
        - [Vp4Describe]
        - [Vp4Shelve]
    - [File editing](#file-editing)
        - [Vp4Add]
        - [Vp4Delete]
        - [Vp4Edit]
        - [Vp4Reopen]
        - [Vp4Revert]
- [Passive Features](#passive-features)
    - [Prompt for edit](#prompt-for-edit)
    - [Open depot file](#open-depot-file)

## Commands

### Analysis

_These commands query and display information about a file._

<div class="command" id="Vp4Annotate">
`:[range]Vp4Annotate`
</div>

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
    | :Pannotate                                                |
    +----------------------------------+------------------------+
```

_Note: Annotations will be misaligned on files that are currently being edited.
This is because `p4 annotate` works only submitted revisions of files.  To
workaround this, it is suggested to open the last submitted revision of the
filelog using `:Vp4Filelog` and run `:Vp4Annotate` on that._

<div class="command" id="Vp4Diff">
`:Vp4Diff [s][p][@{cl}][#{rev}]`
</div>

With no arguments, the depot version of the current file in a vertical split,
in diff mode.  Hit `q` to exit.

- With `[s]` diff with shelved in current changelist.  Only available if file is
  open for edit and shelved.
- With `[p]` diff with previous version.  Available on any file that exists in
  the depot.
- With `[@{cl}]` diff with shelved in changelist `{cl}`.  Available on any file
  that exists in the depot, provided it is actually shelved in changelist.
- With `[#{rev}]` diff with revision `{rev}`.

<div class="command" id="Vp4Filelog">
`:Vp4Filelog`
</div>

Populate the quick-fix or location list with the past revisions of this file.
The file is not actually retrieved from the server until it is opened.  Lists
in chronologically reverse order.

Unset [g:vp4_open_loclist] to prevent the location list from being opened
automatically.  Set [g:vp4_filelog_max] to limit the number of revisions
listed.

### Change specification

_These commands perform actions on changelists._

<div class="command" id="Vp4Change">
`:Vp4Change`
</div>

Opens the change specification in a new split.  Equivalent to `p4 change -o`
if current file is not already opened in a changelist and `p4 change -o -c
{cl}` if already opened in a changelist.  Use the write `:w` command to make
the change, quit `:q` to abort.

<div class="command" id="Vp4Describe">
`:Vp4Describe`
</div>

Opens a preview window containing a description of the changelist in which the
current file is open, obtained from `p4 describe <cl>`

<div class="command" id="Vp4Shelve">
`:Vp4Shelve[!]`
</div>

Calls the shelve command for the current file, for the changelist in which it
is currently open.  Not available unless the file is open in a named
changelist (i.e. not the default changelist).  With `[!]` performs the command
with `-f`, overwriting any existing shelved version.

### File editing

_These commands perform actions on files that alter their state in Perforce._

<div class="command" id="Vp4Add">
`:Vp4Add`
</div>

Opens current file for add.

<div class="command" id="Vp4Delete">
`:Vp4Delete`
</div>

Opens current file for delete.  Unloads current buffer.

<div class="command" id="Vp4Edit">
`:Vp4Edit`
</div>

Opens current file for edit.

<div class="command" id="Vp4Reopen">
`:Vp4Reopen`
</div>

Move the current file to a different changelist.  Lists all open changelists
and prompts for a selection.

<div class="command" id="Vp4Revert">
`:Vp4Revert[!]`
</div>

Reverts current file.  Confirms before doing so.  Use `[!]` to skip
confirmation.

## Passive Features

### Prompt for edit

When writing a file, set [g:vp4_prompt_on_write] to enable prompt on write to
`p4 edit` the file.

### Open depot file

Set [g:vp4_allow_open_depot_file] to allow vim to be invoked on a depot path
specification, like `vim //main/foo/bar/baz.cpp` where:

- if the file has been synced into the workspace, open the local file
- otherwise, fetch the file contents from server

## Options

<div class="option" id="g:vp4_perforce_executable">
`g:vp4_perforce_executable` 

Name of perforce executable.

- p4 (default)

</div>
<div class="option" id="g:vp4_prompt_on_write">
`g:vp4_prompt_on_write`     

Prompt for edit when (force) writing a file that has not already been opened for
edit.

- 0
- 1 (default)

</div>
<div class="option" id="g:vp4_prompt_on_modify">
`g:vp4_prompt_on_modify`    

Prompt for edit when modifying a file that has not already been opened for edit.

- 0 (default)
- 1

</div>
<div class="option" id="g:vp4_diff_suppress_header">
`g:vp4_diff_suppress_header`

Suppress perforce header information in file being diffed

- 0
- 1 (default)

</div>
<div class="option" id="g:vp4_annotate_simple">
`g:vp4_annotate_simple`     

Show only the changelist number when annotating.  Significantly speeds up
[Vp4Annotate] by eliminating calls to `p4 open`.

- 0 (default)
- 1

</div>
<div class="option" id="g:vp4_annotate_revision">
`g:vp4_annotate_revision`   

Show revision number instead of changelist number in which line was changed.
Full annotation (username, date, description) is not available if set.

- 0 (default)
- 1

</div>
<div class="option" id="g:vp4_open_loclist">
`g:vp4_open_loclist`        

Automatically open the location list after performing [Vp4Filelog]

- 0
- 1 (default)

</div>
<div class="option" id="g:vp4_filelog_max">
`g:vp4_filelog_max`         

Limit the number of revisions listed by [Vp4Filelog].  Runs faster with a
smaller limit.

- 10 (default)
- 0 lists all revisions

</div>
<div class="option" id="g:vp4_allow_open_depot_file">
`g:vp4_allow_open_depot_file`

Allow invoking vim with a perforce depot path.  If the file is synced locally,
open that file.  Otherwise, open a new buffer with the server file contents.

## Credits

This plugin was heavily inspired by vim-fugitive.  Additionally, the author
was helped greatly by the book Learn Vimscript the Hard Way and Vim's
excellent built-in documentation.

[g:vp4_perforce_executable]:   #g:vp4_perforce_executable
[g:vp4_prompt_on_write]:       #g:vp4_prompt_on_write
[g:vp4_prompt_on_modify]:      #g:vp4_prompt_on_modify
[g:vp4_diff_suppress_header]:  #g:vp4_diff_suppress_header
[g:vp4_annotate_simple]:       #g:vp4_annotate_simple
[g:vp4_annotate_revision]:     #g:vp4_annotate_revision
[g:vp4_open_loclist]:          #g:vp4_open_loclist
[g:vp4_filelog_max]:           #g:vp4_filelog_max
[g:vp4_allow_open_depot_file]: #g:vp4_allow_open_depot_file

[Vp4Annotate]: #Vp4Annotate
[Vp4Diff]:     #Vp4Diff
[Vp4Filelog]:  #Vp4Filelog
[Vp4Change]:   #Vp4Change
[Vp4Shelve]:   #Vp4Shelve
[Vp4Add]:      #Vp4Add
[Vp4Delete]:   #Vp4Delete
[Vp4Edit]:     #Vp4Edit
[Vp4Reopen]:   #Vp4Reopen
[Vp4Revert]:   #Vp4Revert
