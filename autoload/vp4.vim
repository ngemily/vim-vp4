" File:         vp4.vim
" Description:  vim global plugin for perforce integration
" Last Change:  Nov 22, 2016
" Author:       Emily Ng

" {{{ Explorer global data structures
" directory object data
" dir_data = {
"   '<full path name>' : {
"       'name' : "<name>/",
"       'folded' : <0 folded, 1 unfolded>,
"       'files' : [
"           {'name': <filename>, 'flags': <flags>}, ...
"       ],
"       'children' : [<list of children full path names>]
"   },
"   ...
" }
"
" root = //main
" parent/               //main
"     child/            //main/parent
"         file0.txt     //main/parent/child
"         file1.txt     //main/parent/child
"     file2.txt         //main/parent
let s:directory_data = {}

" line number to directory prefix map
let s:line_map = {}

" depot directory to local directory map
let s:directory_map = {}
" }}}

" {{{ Helper functions

" {{{ Generic Helper functions
function! s:BufferIsEmpty()
    return line('$') == 1 && getline(1) == ''
endfunction

" Pad string by appending spaces until length of string 's' is equal to 'amt'
function! s:Pad(s,amt)
    return a:s . repeat(' ',a:amt - len(a:s))
endfunction

" Pad string by prepending spaces until length of string 's' is equal to 'amt'
function! s:PrePad(s,amt)
    return repeat(' ', a:amt - len(a:s)) . a:s
endfunction

" Echo an error message without the annoying 'Detected error in ...' header
function! s:EchoError(msg)
    echohl ErrorMsg
    echom a:msg
    echohl None
endfunction

" Echo a warning message
function! s:EchoWarning(msg)
    echohl WarningMsg
    echom a:msg
    echohl None
endfunction

function! s:GoToWindowForBufferName(name)
    if bufwinnr(bufnr(a:name)) != -1
        exe bufwinnr(bufnr(a:name)) . "wincmd w"
        return 1
    else
        return 0
    endif
endfunction

" }}}

" {{{ Perforce system functions
" Return result of calling p4 command
function! s:PerforceSystem(cmd)
	if has('win64') || has('win32')
		let command = g:vp4_perforce_executable . " " . a:cmd . " 2> NUL"
	else
		let command = g:vp4_perforce_executable . " " . a:cmd . " 2> /dev/null"
	endif
    if g:perforce_debug
        echom "DBG sys: " . command
    endif
    let retval = system(command)
    return retval
endfunction

" Append results of p4 command to current buffer
function! s:PerforceRead(cmd)
    let _modifiable = &modifiable
    set modifiable
    let command = '$read !' . g:vp4_perforce_executable . " " . a:cmd
    if g:perforce_debug
        echom "DBG read: " . command
    endif
    " Populate the window and get rid of the extra line at the top
    execute command
    1
    execute 'normal! dd'
    let &modifiable=_modifiable
endfunction

" Use current buffer as stdin to p4 command
function! s:PerforceWrite(cmd)
    let command = 'write !' . g:vp4_perforce_executable . " " . a:cmd
    if g:perforce_debug
        echom "DBG write: " . command
    endif
    execute command
endfunction

" Function to get the path of the file
function! s:ExpandPath(file)
    if exists("g:vp4_base_path_replacements")
        if g:perforce_debug	
            echom "We have a base path replacements"
        endif
        let l:oldPath = expand('%:p')
        let l:replacements = items(g:vp4_base_path_replacements)
        for item in l:replacements
            if g:perforce_debug
                echom "does " . l:oldPath . " match " . item[0]
            endif
            if l:oldPath =~ item[0]
                " We have a match
                if g:perforce_debug
                    echom "Matched string " . item[0] . " in " . l:oldPath
                endif
                let l:newFile = substitute(l:oldPath, item[0], item[1], "")
                if g:perforce_debug
                    echom "New path " . l:newFile
                endif
                return l:newFile
            endif
        endfor
        if g:perforce_debug
            echom "Did not find replacement, return"
        endif
        return expand(a:file)
    else
        if g:perforce_debug
            echom "Using default pathing"
        endif
        return expand(a:file)
    endif
endfunction
" }}}

" {{{ Perforce checker infrastructure
" Returns the value of a fstat field
    " Throws an error if it failed.  It is up to the *caller* to catch the error
    " and issue an appropriate message.
function! s:PerforceFstat(field, filename)
    " NB: for some reason fstat was designed not to return an error code if
    "   1. no such file
    "   2. no such revision
    "   3. not shelved in changelist
    " It always starts a valid line with '...'; use it to validate response.
    " It does return -1 if an invalid field was requested.
    let s = s:PerforceSystem('fstat -T ' . a:field . ' ' . a:filename)
    if v:shell_error || matchstr(s, '\.\.\.') == ''
        if matchstr(s, 'P4PASSWD') != ''
            call s:EchoError(split(s, '\n')[0])
            return 0
        else
            throw 'PerforceFstatError'
        endif
    endif

    " Extract the value from the string which looks like:
    "   ... headRev 65\n\n
    let val = split(split(substitute(s, '\r', '', ''), '\n')[0])[2]
    if g:perforce_debug
        echom 'fstat got value ' . val . ' for field ' . a:field
                \ . ' on file ' . a:filename
    endif

    return val
endfunction

" Assert fstat field
function! s:PerforceAssert(field, filename, msg)
    try
        let retval = s:PerforceFstat(a:field, a:filename)
    catch /PerforceFstatError/
        call s:EchoError(a:msg)
        return 0
    endtry
    return retval
endfunction

" Query fstat field
function! s:PerforceQuery(field, filename)
    try
        let retval = s:PerforceFstat(a:field, a:filename)
    catch /PerforceFstatError/
        return 0
    endtry
    return retval
endfunction
" }}}

" {{{ Perforce field checkers

" Tests for existence in depot.  Issues error message upon failure.
    " Can be used to test existence of a specific revision, or shelved in a
    " particular changelist by adding revision specifier to filename.
    "
    " Abbreviated summary:
    "   #n    - revision 'n'
    "   #have - have revision
    "   @=n   - at changelist 'n' (shelved)
function! s:PerforceAssertExists(filename)
    let msg = a:filename . ' does not exist on the server'
    return s:PerforceAssert('headRev', a:filename, msg) != ''
endfunction

" Tests for opened.  Issues error message upon failure.
function! s:PerforceAssertOpened(filename)
    let msg = a:filename . ' not opened for change'
    return  s:PerforceAssert('action', a:filename, msg) != ''
endfunction

" Tests for opened.
function! s:PerforceExists(filename)
    return s:PerforceQuery('headRev', a:filename) != ''
endfunction

" Tests for whether a given path is a directory in perforce
" given either a local path or a server path
function! s:PerforceGetDirectory(filepath)
    let filepath = a:filepath

    " p4 commands do not expect trailing '/'
    if strpart(filepath, strlen(filepath) - 1, 1) == '/'
        let filepath = strpart(filepath, 0, strlen(filepath) - 1)
    endif

    " get server path
    if filepath[0:1] == '//'
        " given server path
        let perforce_filepath = filepath
    else
        " given local path
        let perforce_filepath = filepath
        let command = 'where ' . filepath
        " NB: `p4 where` only works on directories below the root
        "     e.g. `p4 where //main` will fail if 'main' is the root
        let retval = s:PerforceSystem(command)
        if v:shell_error || strlen(retval) == 0
            return ''
        endif
        let perforce_filepath = split(retval)[0]
    endif

    " verify server path
    " TODO potentially use parent directory as input if given file
    let command = 'dirs ' . perforce_filepath
    let retval = s:PerforceSystem(command)
    let retval = trim(retval)
    if v:shell_error || (retval != perforce_filepath)
        return ''
    endif

    return perforce_filepath
endfunction

" Tests for opened.
function! s:PerforceOpened(filename)
    return s:PerforceQuery('action', a:filename) != ''
endfunction

" Return changelist that given file is open in
function! s:PerforceGetCurrentChangelist(filename)
    return s:PerforceQuery('change', a:filename)
endfunction

" Return have revision number
function! s:PerforceHaveRevision(filename)
    return s:PerforceQuery('haveRev', a:filename)
endfunction
" }}}

" {{{ Perforce revision specification helpers
" Return filename with any revision specifier stripped
function! s:PerforceStripRevision(filename)
    return split(a:filename, '#')[0]
endfunction

" Return filename with appended revision specifier
"
" Priority list:
"   1. Embedded revision specifier in filename
"   2. Synced revision
"   3. Head revision (no specifier required)
function! s:PerforceAddRevision(filename)
    " embedded revision
    let embedded_rev = matchstr(a:filename, '#\zs[0-9]\+\ze')
    if embedded_rev != ''
        return a:filename
    endif

    " have revision
    let have_revision = s:PerforceHaveRevision(a:filename)
    if have_revision
        return a:filename . '#' . have_revision
    endif

    " no specifier
    return a:filename
endfunction

" Return filename with appended 'have revision - 1' specifier
    " If editing a file with the revision aleady embedded in the name, return
    " the revision before that instead.
function! s:PerforceAddPrevRevision(filename)
    let embedded_rev = matchstr(a:filename, '#\zs[0-9]\+\ze')
    if embedded_rev != ''
        let prev_rev = embedded_rev - 1
        return substitute(a:filename, embedded_rev, prev_rev, "")
    else
        let prev_rev = s:PerforceHaveRevision(a:filename) - 1
        return a:filename . '#' . prev_rev
    endif
endfunction
" }}}
" }}}

" {{{ Main functions

" {{{ System
function! vp4#PerforceSystemWr(...)
    let cmd = join(map(copy(a:000), 'expand(v:val)'))

    " open a preview window
    pedit __vp4_scratch__
    wincmd P

    " call p4 describe
    normal! ggdG
    silent call s:PerforceRead(cmd)
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap

    " return to original windown
    wincmd p
endfunction
" }}}

" {{{ File editing
" Call p4 add.
function! vp4#PerforceAdd()
    let filename = s:ExpandPath('%')

    call s:PerforceSystem('add ' .filename)
endfunction

" Call p4 delete.
function! vp4#PerforceDelete(bang)
    let filename = s:ExpandPath('%')
    if !s:PerforceAssertExists(filename) | return | endif

    if !a:bang
        let do_delete = input('Are you sure you want to delete ' . filename
                \ . '? [y/n]: ')
    endif

    if a:bang || do_delete ==? 'y'
        call s:PerforceSystem('delete ' .filename)
        bdelete
    endif

endfunction

" Call p4 edit.
function! vp4#PerforceEdit()
    let filename = s:ExpandPath('%')
    if !s:PerforceAssertExists(filename) | return | endif

    call s:PerforceSystem('edit ' .filename)

    " reload the file to refresh &readonly attribute
    execute 'edit ' filename
endfunction

" Call p4 revert.  Confirms before performing the revert.
function! vp4#PerforceRevert(bang)
    let filename = s:ExpandPath('%')
    if !s:PerforceAssertOpened(filename) | return | endif

    if !a:bang
        let do_revert = input('Are you sure you want to revert ' . filename
                \ . '? [y/n]: ')
    endif

    if a:bang || do_revert ==? 'y'
        call s:PerforceSystem('revert ' .filename)
        set nomodified
    endif

    " reload the file to refresh &readonly attribute
    execute 'edit ' filename
endfunction
" }}}

" {{{ Change specification
" Call p4 shelve
function! vp4#PerforceShelve(bang)
    let filename = s:ExpandPath('%')
    if !s:PerforceAssertOpened(filename) | return | endif

    let perforce_command = 'shelve'
    let cl = s:PerforceGetCurrentChangelist(filename)

    if cl !~# 'default'
        let perforce_command .= ' -c ' . cl
        if a:bang | let perforce_command .= ' -f' | endif
        let msg = split(s:PerforceSystem(perforce_command . ' ' . filename), '\n')
        if v:shell_error | call s:EchoError(msg[-1]) | endif
        let msg = filename . ' shelved in p4:' . cl
        echom msg
    else
        call s:EchoError('Files open in the default changelist'
                \ . ' may not be shelved.  Create a changelist first.')
    endif

endfunction

" Use contents of buffer to send a change specification
function! s:PerforceWriteChange()
    silent call s:PerforceWrite('change -i')

    " If the change was made successfully, mark the file as no longer modified
    " (so that Vim doesn't warn user that a file has been modified but not
    " written on exit) and close the window.
    "
    " Note: leaves an open buffer.  Unloading a buffer in an autocommand issues
    " an error message, so this buffer has been intentionally left open by the
    " author.
    if !v:shell_error
        set nomodified
        close
    endif
endfunction

" Call p4 change
    " Uses the -o/-i options to avoid the confirmation on abort.
    " Works by opening a new window to write your change description.
function! vp4#PerforceChange()
    let filename = s:ExpandPath('%')
    let perforce_command = 'change -o'
    let lnr = 25

    " If this file is already in a changelist, allow the user to modify that
    " changelist by calling `p4 change -o <cl#>`.  Otherwise, call for default
    " changelist by omitting the changelist argument.
    if s:PerforceOpened(filename)
        let changelist = s:PerforceGetCurrentChangelist(filename)
        if changelist
            let perforce_command .= ' ' . changelist
            let lnr = 27
        endif
    endif

    " Open a new split to hold the change specification.  Clear it in case of
    " any previous invocations.
    topleft new __vp4_change__
    normal! ggdG

    silent call s:PerforceRead(perforce_command)

    " Reset the 'modified' option so that only user modifications are captured
    set nomodified

    " Put cursor on the line where users write the changelist description.
    execute lnr

    " Replace write command (:w) with call to write change specification.
    " Prevents the buffer __vp4_change__ from being written to disk
    augroup WriteChange
        autocmd! * <buffer>
        autocmd BufWriteCmd <buffer> call <SID>PerforceWriteChange()
    augroup END
endfunction

" Call `p4 describe` on the changelist of the current file, if any.  Show the
" output in a preview window.
function! vp4#PerforceDescribe()

    let filename = s:ExpandPath('%')
    let current_changelist = s:PerforceGetCurrentChangelist(filename)

    if !current_changelist
        call s:EchoWarning(filename . ' is not open in a named changelist')
        return
    endif

    " open a preview window
    pedit __vp4_describe__
    wincmd P

    " call p4 describe
    normal! ggdG
    let perforce_command = "describe " . current_changelist
    silent call s:PerforceRead(perforce_command)
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap

    " return to original windown
    wincmd p
endfunction

" Prompt the user to move file currently being edited to a different changelist.
    " Present the user with a list of current changes.
function! vp4#PerforceReopen()
    let filename = s:ExpandPath('%')
    if !s:PerforceAssertOpened(filename) | return | endif

    " Get the pending changes in the current client
    let perforce_command = "changes -u $USER -s pending -c $P4CLIENT"
    let changes = split(s:PerforceSystem(perforce_command), '\n')

    " Prepend with choice numbers, starting at 1
    call map(changes, 'v:key + 1 . ". " . v:val')

    " Prompt the user
    let currentchangelist = s:PerforceGetCurrentChangelist(filename)
    echom filename . ' is currently open in change "' . currentchangelist
            \ . '" Select a changelist to move to: '
    let change = inputlist(changes + [len(changes) + 1 . '. default'])

    " From the user's input, get the actual changelist number
    if !change | return | endif
    let change_number = change > len(changes) ? 'default'
            \ : split(changes[change - 1], ' ')[2]
    echom 'Moving ' . filename . ' to change ' . change_number

    " Perform the reopen command
    let perforce_command = 'reopen -c ' . change_number . ' ' . filename
    call s:PerforceSystem(perforce_command)
endfunction
" }}}

" {{{ Analysis
" Open repository revision in diff mode
    "  Options:
    "  s       diffs with shelved in file's current changelist
    "  @cl     diffs with shelved in given changelist
    "  p       diffs with previous revision (i.e. have revision - 1)
    "  #rev    diffs with given revision
    "  <none>  diffs with have revision
function! vp4#PerforceDiff(...)
    let filename = s:ExpandPath('%')

    " Check for options
    "   'a:0' is set to the number of extra arguments
    "   a:1 is the first extra argument, a:2 the second, etc.
    " @cl: Diff with shelved in a:1
    if a:0 >= 1 && a:1[0] == '@'
        let cl = split(a:1, '@')[0]
        let filename .= '@=' . trim(cl)
    " #rev: Diff with revision a:1
    elseif a:0 >= 1 && a:1[0] == '#'
        let filename = s:PerforceStripRevision(filename) . trim(a:1)
    " s: Diff with shelved in current changelist
    elseif a:0 >= 1 && a:1 =~? 's'
        let filename .= '@=' . s:PerforceGetCurrentChangelist(filename)
    " p: Diff with previous version
    elseif a:0 >= 1 && a:1 =~? 'p'
        let filename = s:PerforceAddPrevRevision(filename)
    " default: diff with have revision
    else
        if !s:PerforceAssertOpened(filename) | return | endif
        let filename .= '#have'
    endif

    " Assert valid revision
    if !s:PerforceAssertExists(filename) | return | endif

    " Setup current window
    let filetype = &filetype
    diffthis

    " Create the new window and populate it
    execute 'leftabove vnew ' . shellescape(filename, 1)
    let perforce_command = 'print'
    if g:vp4_diff_suppress_header
        let perforce_command .= ' -q'
    endif
    let perforce_command .= ' ' . shellescape(filename, 1)
    silent call s:PerforceRead(perforce_command)

    " Set local buffer options
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    setlocal nomodifiable
    setlocal nomodified
    execute "set filetype=" . filetype
    diffthis
    nnoremap <buffer> <silent> q :<C-U>bdelete<CR> :windo diffoff<CR>
endfunction

" Syntax highlighting for annotation data
function! s:PerforceAnnotateHighlight()
    syn match VP4Change /\v\d+$/
    syn match VP4Date /\v\d{4}\/\d{2}\/\d{2}/
    syn match VP4Time /\v\d{2}:\d{2}:\d{2}( [A-Z]{3})?/

    hi def link VP4Change Number
    hi def link VP4Date Comment
    hi def link VP4Time Comment
    hi def link VP4User Keyword
endfunction

" Populate change metadata, namely: user, date, description.  Assumes buffer
    " contains one changelist number per line.
function! s:PerforceAnnotateFull(lbegin, lend)
    let data = {}
    let last_cl = 0

    set modifiable
    let lnr = a:lbegin
    while lnr && lnr <= a:lend
        let line = getline(lnr)

        " Only query the changelist information from perforce if we have not
        " seen this change before.  While this could take up significant amounts
        " of memory for a large file, it should still be much faster than
        " additional calls to `p4 change`
        if !has_key(data, line)
            let data[line] = {}
            let cl_data = split(s:PerforceSystem('change -o ' . line), '\n')

            try
                let description_index = match(cl_data, '^Description')
                let data[line]['description'] = substitute(join(cl_data[description_index + 1:-1]),
                        \ "\t", "", "g")

                " Format: 'Date:\t<date> <time>'
                let date_index = match(cl_data, '^Date')
                let date = split(split(cl_data[date_index], '\t')[1], ' ')[0]
                let data[line]['date'] = date

                let user_index = match(cl_data, '^User')
                let user = split(cl_data[user_index], '\t')[1]
                let data[line]['user'] = s:PrePad(user, 8)

                " [Hack] Conveniently use the fact that we have the user name
                " now to identify it as a keyword for highlighting later.
                execute " syn keyword VP4User " . data[line]['user']
            catch
                echom 'failed to get data for change ' . line
                if g:perforce_debug
                    echom join(cl_data)
                endif
                continue
            endtry
        endif

        " Small state machine to display the description for the current
        " changelist.  First line shows the date and user, subsequent lines show
        " the continue description, if it exceeds one line.
        let LEN = 70
        if line != last_cl
            let idx = 0
            call setline(lnr, ' '
                    \ . ' ' . data[line]['date']
                    \ . ' ' . data[line]['user']
                    \ . ' ' . line
                    \ )
        else
            let description = strpart(data[line]['description'], idx, LEN)
            call setline(lnr, s:Pad(description, LEN)
                    \ . ' ' .line
                    \ )
            let idx += LEN
        endif

        let last_cl = line
        let lnr = nextnonblank(lnr + 1)
    endwhile

    set nomodifiable
endfunction

" Open a scrollbound split containing on each line the changelist number in
    " which it was last edited.  Accepts a range to limit the section being
    " fully annotated.
function! vp4#PerforceAnnotate(...) range
    let filename = s:ExpandPath('%:p')
    if !s:PerforceAssertExists(filename) | return | endif

    " `p4 annotate` can only operate on revisions that exist in the depot.  If a
    " file is open for edit, only the annotations for the #have revision can be
    " given.  Issue a warning of the user tries to do this.
    if s:PerforceOpened(filename)
        call s:EchoWarning(filename
                \ . ' is open for edit, annotations will likely be misaligned')
    endif

    " Use revision specific perforce commands
    let filename = s:PerforceAddRevision(filename)

    " Save the cursor position and buffer number
    let saved_curpos = getcurpos()
    let saved_bufnr = bufnr(bufname("%"))

    " Open a split and perform p4 annotate command
    silent leftabove vnew Vp4Annotate
    let perforce_command = 'annotate -q'
    if !g:vp4_annotate_revision
        let perforce_command .= ' -c'
    endif
    let perforce_command .= ' ' . shellescape(filename, 1) . '| cut -d: -f1'
    call s:PerforceRead(perforce_command)

    " Perform full annotation
    if !(a:0 > 0 && a:1 == 'q') && !g:vp4_annotate_revision
        call s:PerforceAnnotateFull(a:firstline, a:lastline)
    endif

    " Clean up buffer, set local options, move cursor to saved position
    set modifiable
    %right 80
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    setlocal nonumber norelativenumber
    call s:PerforceAnnotateHighlight()
    call setpos('.', saved_curpos)
    set cursorbind scrollbind
    vertical resize 80
    set nomodifiable

    " q to exit
    nnoremap <buffer> <silent> q :<C-U>bdelete<CR>
            \ :windo set noscrollbind nocursorbind<CR>

    " Go back to original buffer
    execute bufwinnr(saved_bufnr) . "wincmd w"
    set cursorbind scrollbind
    syncbind
endfunction

" Populate the quick-fix or location list with the past revisions of this file.
    " Only lists the files and some changelist data.  The file is not retrieved
    " until the user opens it.
function! vp4#PerforceFilelog(...)
    let max_history = g:vp4_filelog_max
    if a:0 > 0
        let max_history = a:1
    endif

    let filename = s:PerforceStripRevision(s:ExpandPath('%'))
    if !s:PerforceAssertExists(filename) | return | endif

    " Remember some stuff about this file
    let g:_vp4_filetype = &filetype
    let g:_vp4_curpos = getcurpos()

    " Set up the command.  Limit the maximum number of entries.
    let command = 'filelog'
    if g:vp4_filelog_max > 0
        let command .= ' ' . '-m ' . max_history
    endif
    let command .= ' ' . filename

    " Compile all the location list data
    let data = []
    for line in split(s:PerforceSystem(command), '\n')
        let fields = split(line, '\s')

        " Cheap way to filter out irrelevant lines such as just the filename
        " (which is the first line), or 'branch into' lines
        if len(fields) < 8
            continue
        endif

        " Set up dictionary entry
        let entry = {}
        let entry['filename'] = filename . fields[1]
        let entry['lnum'] = g:_vp4_curpos[1]
        let entry['text'] = join(fields[2:-1])

        " Add it to the list
        call add(data, entry)
    endfor

    " Populate the location list
    call setloclist(0, data)

    " Automatically open quick-fix or location list
    if g:vp4_open_loclist
        lopen
    endif

    " Set auto command for opening specific revisions of files
    augroup OpenRevision
        autocmd!
        autocmd BufEnter *#* call <SID>PerforceOpenRevision()
    augroup END
endfunction
" }}}

" {{{ Passive (called by auto commands)
" Check if file exists in the depot and is not already opened for edit.  If so,
" prompt user to open for edit.
function! vp4#PromptForOpen()
    let filename = s:ExpandPath('%')
    if &readonly && s:PerforceAssertExists(filename)
        let do_edit = input(filename .
                \' is not opened for edit.  p4 edit it now? [y/n]: ')
        if do_edit ==? 'y'
            setlocal autoread
            call s:PerforceSystem('edit ' .filename)
        endif
    endif
endfunction

" Expected to be called from opening file populated in quickfix list by
    " Vp4Filelog command.  Works by calling 'p4 print', and the filename already
    " has the revision specifier on the end.
function! s:PerforceOpenRevision()
    " Use buftype as a way to see if we've already gotten this file.
    if &buftype == 'nofile'
        return
    else
        setlocal buftype=nofile
    endif

    let filename = s:ExpandPath('%')
    if !s:PerforceAssertExists(filename) | return | endif

    " Print the file to this buffer
    silent call s:PerforceRead('print -q ' . shellescape(filename, 1))
    setlocal nomodifiable

    " Use the information we remembered about the file where Filelog was invoked
    execute 'setlocal filetype=' . g:_vp4_filetype
    execute g:_vp4_curpos[1]

endfunction

" Open the local file if it exists, otherwise print the contents from the
" server.
"   //main/foo.cpp      opens haveRev or headRev
"   //main/foo.cpp#2    opens #2
"   foo.cpp#2           opens #2
"   foo.cpp             does nothing
function! vp4#CheckServerPath(filename)
    " " FIXME
    " " doesn't work on VimEnter
    " " leaves undesired empty buffer
    " let perforce_directory = s:PerforceGetDirectory(a:filename)
    " if (perforce_directory != '')
    "     call vp4#PerforceExplore(a:filename)
    " endif

    " test for existence of depot file
    if !s:PerforceExists(a:filename) | return | endif

    let requested_rev = matchstr(a:filename, '#[0-9]\+')
    let requested_rev = strpart(requested_rev, 1)

    " check for existence of local file
    let have_rev = s:PerforceQuery('haveRev', a:filename)
    let client_file = s:PerforceQuery('clientFile', a:filename)
    if (len(requested_rev) == 0 || have_rev == requested_rev) && filereadable(client_file)
        let old_bufnr = bufnr('%')
        let old_bufname = bufname('%')
        execute 'edit ' . client_file
        let new_bufnr = bufnr('%')
        let new_bufname = bufname('%')

        if g:perforce_debug
            echom 'old: ' . old_bufnr . ' ' . old_bufname
            echom 'new: ' . new_bufnr . ' ' . new_bufname
        endif

        execute 'buffer ' . new_bufnr
        execute 'doauto BufRead'
        execute 'bdelete! ' . old_bufname

        return
    endif

    " get the file contents
    let perforce_command = 'print '
    if g:vp4_print_suppress_header
        let perforce_command .= ' -q '
    endif
    let perforce_command .= shellescape(a:filename, 1)
    call s:PerforceRead(perforce_command)

    " get filetype
    execute 'doauto BufRead ' . substitute(a:filename, '#.*', '', '')

    setlocal buftype=nofile
    setlocal nomodifiable

endfunction

" }}}

" {{{ Depot explorer

" Print file contents to temporary buffer for viewing without syncing
function! s:ExplorerPreviewOrOpen()
    if len(getline('.')) == 0 | return | endif

    let filename = split(getline('.'))[0]
    let directory = s:line_map[line(".")]
    let fullpath = directory . filename
    let local_path = s:directory_map[directory] . s:PerforceStripRevision(filename)

    " file
    rightbelow new
    let local_path = s:directory_map[directory] . s:PerforceStripRevision(filename)
    if filereadable(local_path)
        let command  = 'edit ' . local_path
        exe command
    else
        call vp4#CheckServerPath(fullpath)
    endif
endfunction

" Sync or open file under cursor, non-recursive
function! s:ExplorerSyncOrOpen(split_command)
    if len(getline('.')) == 0 | return | endif

    let filename = split(getline('.'))[0]
    let directory = s:line_map[line(".")]
    let fullpath = directory . filename
    let local_path = s:directory_map[directory] . s:PerforceStripRevision(filename)

    " sync if necessary
    if !filereadable(local_path)
        let command = 'sync ' . g:vp4_sync_options . ' ' . s:PerforceStripRevision(fullpath)
        call s:PerforceSystem(command)
    endif

    " open file in new vsplit
    exe a:split_command
    let command  = 'edit ' . local_path
    exe command
endfunction

" Change explorer root to selected directory
function! s:ExplorerChange()
    if len(getline('.')) == 0 | return | endif

    let filename = split(getline('.'))[0]
    if strpart(filename, strlen(filename) - 1, 1) != '/' | return | endif

    let fullpath = s:line_map[line(".")] . filename
    let s:directory_data[fullpath]['folded'] = 0
    call s:ExplorerPopulate(fullpath)
    call s:ExplorerRender(fullpath, 0, s:FilepathHead(fullpath))

    call setpos(".", [0, 2, 0, 0])
endfunction

" If on a directory, toggle the directory.
" If on a file, go to that file.
function! s:ExplorerGoTo()
    if len(getline('.')) == 0 | return | endif

    let filename = split(getline('.'))[0]
    let directory = s:line_map[line(".")]
    let fullpath = directory . filename
    if strpart(filename, strlen(filename) - 1, 1) == '/'
        " directory

        " populate if not populated
        let d = get(s:directory_data, fullpath)
        if !has_key(d, 'files')
            call s:ExplorerPopulate(fullpath)
        else
            " toggle fold/unfold
            let d.folded = !d.folded
        endif

        let saved_curpos = getcurpos()
        call s:ExplorerRender(g:explorer_key)
        call setpos('.', saved_curpos)
    else
        " file
        call s:ExplorerSyncOrOpen('')
    endif
endfunction

" Return head of a:filepath
function! s:FilepathHead(filepath)
    let path = split(a:filepath, '/')
    call remove(path, -1)
    return '//' . join(path, '/') . '/'
endfunction

" Set explorer root node to its parent
function! s:ExplorerPop()
    let path = s:FilepathHead(g:explorer_key)
    if len(split(path, '/')) == 0 | return | endif
    call s:ExplorerPopulate(path)
    let s:directory_data[path]['folded'] = 0
    call s:ExplorerRender(path)
endfunction

" Render the directory data as a tree, using given node as the root.  This node
" should be a directory.
function! s:ExplorerRender(key, ...)
    setlocal modifiable
    let key = a:key
    if strpart(a:key, strlen(a:key) - 1, 1) != '/'
        let key .= '/'
    endif

    " default
    let level = 0
    let root  = s:FilepathHead(key)

    if a:0 > 0
        let level = a:1
        let root  = a:2
    endif
    " Clear screen before rendering
    if level == 0
        let g:explorer_key = key
        silent normal! ggdG
    endif

    " Setup
    let d = get(s:directory_data, key)
    let prefix = repeat(' ', level * 4)

    " Print myself
    call append(line('$'), prefix . d.name)
    let s:line_map[line("$")] = root

    " Print my children
    if !d.folded
        " print directories
        for child in get(d, 'children', [])
            call s:ExplorerRender(child, level + 1, root . d.name)
        endfor

        " print files
        let prefix .= repeat(' ', 4)
        for file_obj in get(d, 'files')
            call append(line('$'), prefix . file_obj['name'] . file_obj['flags'])
            let s:line_map[line("$")] = root . d.name
        endfor
    endif

endfunction

" Populate directory data at given node
function! s:ExplorerPopulate(filepath)
    let perforce_filepath = a:filepath
    if strpart(a:filepath, strlen(a:filepath) - 1, 1) != '/'
        let perforce_filepath .= '/'
    endif
    if g:perforce_debug
        echom 'Populating "' . perforce_filepath . '" ...'
    endif

    if !has_key(s:directory_data, perforce_filepath)
        let s:directory_data[perforce_filepath] = {
                    \'name' : split(perforce_filepath, '/')[-1] . '/',
                    \'folded' : 0,
                    \}
    else
        let s:directory_data[perforce_filepath]['folded'] = 0
    endif

    if !has_key(s:directory_map, perforce_filepath)
        " `where` fails for root of depot, when popping directory stack
        let command = 'where ' . strpart(perforce_filepath, 0, strlen(perforce_filepath) - 1)
        let retval = s:PerforceSystem(command)
        if v:shell_error || strlen(retval) == 0
            let s:directory_map[perforce_filepath] = '/'
        else
            let local_path = split(retval)[-1]
            let s:directory_map[perforce_filepath] = local_path . '/'
        endif
    endif

    if !has_key(s:directory_data[perforce_filepath], 'files')
        let pattern = '"' . perforce_filepath . '*"'

        " Populate directories
        let perforce_command = 'dirs ' . pattern
        let dirnames = split(s:PerforceSystem(perforce_command), '\n')
        call map(dirnames, 'v:val . "/"')
        for dirname in dirnames
            if !has_key(s:directory_data, dirname)
                let s:directory_data[dirname] = {
                            \'name' : split(dirname, '/')[-1] . '/',
                            \'folded' : 1
                            \}
            endif
        endfor

        " Populate files
        let perforce_command = 'files -e ' . pattern
        let filepaths = split(s:PerforceSystem(perforce_command), '\n')
        let filenames = []
        for filepath in filepaths
            let filename = split(split(filepath)[0], '/')[-1]
            let local_path = s:directory_map[perforce_filepath] . s:PerforceStripRevision(filename)
            if filereadable(local_path)
                let flags = "*"
            else
                let flags = ""
            endif
            let obj = {
                        \'name' : filename,
                        \'flags' : flags,
                        \}
            call add(filenames, obj)
        endfor
        " Neovim does not support calling map with function objects
        " call map(filepaths, {idx, val -> split(split(val)[0], '/')[-1]})

        let s:directory_data[perforce_filepath]['children'] = dirnames
        let s:directory_data[perforce_filepath]['files'] = filenames
    endif

endfunction

" Open the depot file explorer
" :Vp4Explore()               - opens at current file's directory
" :Vp4Explore('.')            - opens at cwd
" :Vp4Explore('//depot/path') - opens at '//depot/path'
" :Vp4Explore('/local/path')  - opens at 'local/path'
function! vp4#PerforceExplore(...)
    let filepath = ''
    let perforce_filepath = ''

    if a:0 > 0
        let filepath = trim(a:1)
    else
        let filepath = expand('%:p:h')
    endif

    let perforce_filepath = s:PerforceGetDirectory(filepath)
    if perforce_filepath == ''
        call s:EchoWarning("Unable to resolve a Perforce directory.")
        return
    endif

    " buffer setup
    if !(s:GoToWindowForBufferName('Depot'))
        silent leftabove vnew Depot
        setlocal buftype=nofile
        setlocal nobuflisted
    endif

    call s:ExplorerPopulate(perforce_filepath)
    call s:ExplorerRender(perforce_filepath)

    " mappings
    nnoremap <script> <silent> <buffer> <CR> :call <sid>ExplorerGoTo()<CR>
    nnoremap <script> <silent> <buffer> -    :call <sid>ExplorerPop()<CR>
    nnoremap <script> <silent> <buffer> c    :call <sid>ExplorerChange()<CR>
    nnoremap <script> <silent> <buffer> s    :call <sid>ExplorerSyncOrOpen('rightbelow new')<CR>
    nnoremap <script> <silent> <buffer> v    :call <sid>ExplorerSyncOrOpen('rightbelow vnew')<CR>
    nnoremap <script> <silent> <buffer> t    :call <sid>ExplorerSyncOrOpen('rightbelow tab new')<CR>
    nnoremap <script> <silent> <buffer> q    :quit<CR>

    " syntax
    syn match Vp4Dir /\v.*\//
    syn match Vp4Rev /\v#.*/

    hi def link Vp4Dir Identifier
    hi def link Vp4Rev Comment
endfunction
" }}}
" }}}

" vim: foldenable foldmethod=marker
