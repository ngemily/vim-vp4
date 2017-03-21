vp4
===
*vim-perforce integration*

Features
--------

* Provides commands for interacting with perforce while remaining in Vim
* Automatically detects operations on files not open for edit
* Ridiculously functional annotation by adding more useful information such as the date, user, and description of the changelist
* Fantastical diffing, including vs depot, vs shelved, vs previous rev
* File history browsing, with with you can (fairly) easily diff two arbitrary revisions of any file

Commands
--------

### ANALYSIS
_These commands query and display information about a file._

    Annotate.|Vp4Annotate|
    Diff.....|Vp4Diff|
    Filelog..|Vp4Filelog|

### CHANGE SPECIFICATION
_These commands perform actions on changelists._

    Change...|Vp4Change|
    Shelve...|Vp4Shelve|

### FILE EDITING 
_These commands perform actions on files that alter their state in Perforce._

    Add......|Vp4Add|
    Delete...|Vp4Delete|
    Edit.....|Vp4Edit|
    Reopen...|Vp4Reopen|
    Revert...|Vp4Revert|

See the docs for details.

Install
-------

Preferred install through a plugin manager, such as Vundle.  See plugin manager
documentation for details.

### Manual install

Clone or download and unzip repo.  Then:

    cp plugin/vp4.vim ~/.vim/plugin
    cp doc/vp4.txt ~/.vim/doc
    vim +helptags ~/.vim/doc +quit
