" File:         vp4.vim
" Description:  vim global plugin for perforce integration
" Last Change:  Nov 22, 2016
" Author:       Emily Ng

""" Initialization
if exists('g:loaded_vp4') || !executable('p4') || &cp
    finish
endif
let g:loaded_vp4 = 1

function! vp4#sid()
    return maparg('<SID>', 'n')
endfunction
nnoremap <SID> <SID>

" Options
function! s:set(var, default)
  if !exists(a:var)
    if type(a:default)
      execute 'let' a:var '=' string(a:default)
    else
      execute 'let' a:var '=' a:default
    endif
  endif
endfunction

call s:set('g:vp4_perforce_executable', 'p4')
call s:set('g:vp4_prompt_on_write', 1)
call s:set('g:vp4_prompt_on_modify', 0)
call s:set('g:vp4_annotate_simple', 0)
call s:set('g:vp4_annotate_revision', 0)
call s:set('g:vp4_open_loclist', 1)
call s:set('g:vp4_filelog_max', 10)
call s:set('g:perforce_debug', 0)

""" Helper functions
" Pad string by appending spaces until length of string 's' is equal to 'amt'
function! s:Pad(s,amt)
    return a:s . repeat(' ',a:amt - len(a:s))
endfunction

" Pad string by prepending spaces until length of string 's' is equal to 'amt'
function! s:PrePad(s,amt)
    return repeat(' ', a:amt - len(a:s)) . a:s
endfunction

" Return result of calling p4 command
function! s:PerforceSystem(cmd)
    let command = g:vp4_perforce_executable . " " . a:cmd
    if g:perforce_debug
        echom "DBG: " . command
    endif
    return system(command)
endfunction

" Append results of p4 command to current buffer
function! s:PerforceRead(cmd)
    let command = '$read !' . g:vp4_perforce_executable . " " . a:cmd
    if g:perforce_debug
        echom "DBG: " . command
    endif
    execute command
endfunction

" Use current buffer as stdin to p4 command
function! s:PerforceWrite(cmd)
    let command = 'write !' . g:vp4_perforce_executable . " " . a:cmd
    if g:perforce_debug
        echom "DBG: " . command
    endif
    execute command
endfunction

" Possible scenarios:
" Valid file:
"   - file not under client root
"   - file not on client
" Opened file:
"   - file not on client and opened for add
"   - file on client and opened for delete
"   - file on client and opened for edit
" Shelved file:
"   - file shelved

" Tests for both existence and opened
function! s:PerforceValidAndOpen(filename)
    if !s:PerforceValid(a:filename)
        return 0
    endif
    if g:perforce_debug
        echom matchstr(s:PerforceSystem('opened ' . a:filename), 'not.*client')
    endif
    return matchstr(s:PerforceSystem('opened ' . a:filename),
            \ 'not.*client') == ''
endfunction

" Tests only for opened.
function! s:PerforceOpened(filename)
    if g:perforce_debug
        echom matchstr(s:PerforceSystem('opened ' . a:filename),
                \ 'not opened on this client')
    endif
    return matchstr(s:PerforceSystem('opened ' . a:filename),
            \ 'not opened on this client') == ''
endfunction

" Tests only for existence in depot
function! s:PerforceValid(filename)
    if g:perforce_debug
        echom matchstr(s:PerforceSystem('have ' . a:filename), 'not.*client')
    endif
    return matchstr(s:PerforceSystem('have ' . a:filename),
            \ 'not.*client') == ''
endfunction

" Test if 'filename' in shelved in changelist 'cl'
function! s:PerforceIsShelved(filename, cl)
    " Files on default changelist cannot be shelved
    if a:cl == 'default'
        return 0
    endif

    " Construct revision specification and test for shelved file
    let file_specification = a:filename . '@=' . a:cl
    if g:perforce_debug
        echom matchstr(s:PerforceSystem('print ' . file_specification),
                \ 'no file.*changelist number')
    endif
    return matchstr(s:PerforceSystem('print ' . file_specification),
            \ 'no file.*changelist number') == ''
endfunction

" Return changelist that given file is open in
function! s:PerforceGetCurrentChangelist(filename)
    return split(s:PerforceSystem('fstat ' . a:filename
                \ . ' | grep change | cut -d " " -f3'), '\n')[0]
endfunction

" Return have revision number
function! s:PerforceHaveRevision(filename)
    let rev = matchstr(s:PerforceSystem('have ' . a:filename), '#\zs[0-9]\+\ze')
    if g:perforce_debug
        echom 'have revision ' . rev . ' of file ' . a:filename
    endif
    return rev
endfunction

" Return filename with appended 'have revision' specifier
function! s:PerforceAddHaveRevision(filename)
    let rev = matchstr(s:PerforceSystem('have ' . a:filename), '#\zs[0-9]\+\ze')
    if g:perforce_debug
        echom 'have revision ' . rev . ' of file ' . a:filename
    endif
    return a:filename . '\#' . rev
endfunction

""" Main functions
" Open repository revision in diff mode
    "  Options:
    "  s       diffs with shelved in file's current changelist
    "  s <cl>  diffs with shelved in given changelist
function! s:PerforceDiff(...)
    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom filename . ' not perforce file opened for edit'
        return
    endif

    " Check for options
    if a:0 >= 1 && type(a:1) == 0
        " Diff with shelved in a:1
        let cl = a:1
        " Verify that the file is indeed shelved
        if s:PerforceIsShelved(filename, cl)
            let filename .= '@=' . cl
        else
            echom filename . 'is not shelved on change ' . cl
            return
        endif
    elseif a:0 >= 1 && a:1 =~? 's'
        " Diff with shelved in current changelist
        let cl = s:PerforceGetCurrentChangelist(filename)

        " Verify that the file is indeed shelved
        if s:PerforceIsShelved(filename, cl)
            let filename .= '@=' . cl
        else
            echom filename . 'is not shelved on change ' . cl
            return
        endif
    elseif a:0 >= 1 && a:1 =~? 'p'
        " Diff with previous version
        let have_rev = s:PerforceHaveRevision(filename)
        let prev_rev = have_rev - 1
        let filename .= '#' . prev_rev

        " If current revision is #1, its previous revision will be invalid.
        if !s:PerforceValid(filename)
            echom 'invalid revision' . filename
            return
        endif
    else
        " default: diff with have revision
        if !s:PerforceValidAndOpen(filename)
            echom 'file not open for edit'
            return
        endif
        let filename = s:PerforceAddHaveRevision(filename)
    endif

    " Setup current window
    let filetype = &filetype
    diffthis

    " Create the new window and populate it
    leftabove vnew
    let perforce_command = 'print ' . shellescape(filename, 1)
    silent call s:PerforceRead(perforce_command)

    " Set local buffer options
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    setlocal nomodifiable
    execute "set filetype=" . filetype
    diffthis
    nnoremap <buffer> <silent> q :<C-U>bdelete<CR> :windo diffoff<CR>
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

" Call p4 add.
function! s:PerforceAdd()
    let filename = expand('%')

    call s:PerforceSystem('add ' .filename)
endfunction

" Call p4 delete.
function! s:PerforceDelete()
    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom 'not a valid perforce file'
        return
    endif

    call s:PerforceSystem('delete ' .filename)
    bdelete
endfunction

" Call p4 edit.
function! s:PerforceEdit()
    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom 'not a valid perforce file'
        return
    endif

    call s:PerforceSystem('edit ' .filename)

    " reload the file to refresh &readonly attribute
    execute 'edit ' filename
endfunction

" Call p4 shelve
function! s:PerforceShelve(bang)
    let filename = expand('%')
    if !s:PerforceValidAndOpen(filename)
        echom 'not a perforce file open for edit'
        return
    endif

    let perforce_command = 'shelve'
    let cl = s:PerforceGetCurrentChangelist(filename)

    if cl !~# 'default'
        let perforce_command .= ' -c ' . cl
        if a:bang | let perforce_command .= ' -f' | endif
        call s:PerforceSystem(perforce_command . ' ' . filename)
    else
        echom 'Files open in the default changelist may not be shelved.  '
                \ . 'Create a changelist first.'
    endif

endfunction

" Call p4 revert.  Confirms before performing the revert.
function! s:PerforceRevert(bang)
    let filename = expand('%')
    if !s:PerforceOpened(filename)
        echom 'not a perforce file opened for edit'
        return
    endif

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

" Call p4 change
    " Uses the -o/-i options to avoid the confirmation on abort.
    " Works by opening a new window to write your change description.
function! s:PerforceChange()
    " Open a new split to hold the change specification.  Clear it in case of
    " any previous invocations.
    topleft new __perforce_change__
    normal! ggdG

    " If this file is already in a changelist, allow the user to modify that
    " changelist by calling `p4 change -o <cl#>`.  Otherwise, call for default
    " changelist by omitting the changelist argument.
    let perforce_command = 'change -o'
    let filename = expand('%')
    if s:PerforceOpened(filename)
        let changelist = s:PerforceGetCurrentChangelist(filename)
        if changelist
            let perforce_command .= ' ' . changelist
            let lnr = 28
        endif
    else
        let lnr = 26
    endif
    silent call s:PerforceRead(perforce_command)

    " Reset the 'modified' option so that only user modifications are captured
    set nomodified

    " Put cursor on the line where users write the changelist description.
    execute lnr

    " Replace write command (:w) with call to write change specification.
    " Prevents the buffer __perforce_change__ from being written to disk
    augroup WriteChange
        autocmd! * <buffer>
        autocmd BufWriteCmd <buffer> call <SID>PerforceWriteChange()
    augroup END
endfunction

" Prompt the user to move file currently being edited to a different changelist.
    " Present the user with a list of current changes.
function! s:PerforceReopen()
    let filename = expand('%')
    if !s:PerforceOpened(filename)
        echom 'not a perforce file opened for edit'
        return
    endif

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

" Check if file exists in the depot and is not already opened for edit.  If so,
" prompt user to open for edit.
function! s:PromptForOpen()
    let filename = expand('%')
    if &readonly && s:PerforceValid(filename)
        let do_edit = input(filename .
                \' is not opened for edit.  p4 edit it now? [y/n]: ')
        if do_edit ==? 'y'
            call s:PerforceSystem('edit ' .filename)
        endif
    endif
endfunction

" Syntax highlighting for annotation data
function! s:PerforceAnnotateHighlight()
    syn match VP4Change /\v\d+$/
    syn match VP4Date /\v\d{4}\/\d{2}\/\d{2}/

    hi def link VP4Change Number
    hi def link VP4Date Comment
    hi def link VP4User Keyword
endfunction

" Populate change metadata, namely: user, date, description.  Assumes buffer
    " contains one changelist number per line.
function! s:PerforceAnnotateFull(lbegin, lend)
    let data = {}
    let last_cl = 0

    let lnr = a:lbegin
    while lnr && lnr <= a:lend
        let line = getline(lnr)

        " Only query the changelist information from perforce if we have not
        " seen this change before.  While this could take up significant amounts
        " of memory for a large file, it should still be much faster than
        " additional calls to `p4 change`
        if !has_key(data, line)
            let data[line] = {}
            let cl_data = split(system('p4 change -o ' . line), '\n')

            try
                let data[line]['date'] = split(split(cl_data[17], '\t')[1], ' ')[0]
                let data[line]['user'] = s:PrePad(split(cl_data[21], '\t')[1], 8)
                let data[line]['description'] = substitute(join(cl_data[26:-1]),
                        \ "\t", "", "g")

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
        if line != last_cl
            let idx = 0
            let LEN = 40
            call setline(lnr, strpart(data[line]['description'], idx, LEN)
                    \ . ' ' . data[line]['date']
                    \ . ' ' . data[line]['user']
                    \ . ' ' . line
                    \ )
        else
            let idx += LEN
            let LEN = 60
            call setline(lnr, strpart(data[line]['description'], idx, LEN)
                    \ . ' ' .line
                    \ )
        endif

        let last_cl = line
        let lnr = nextnonblank(lnr + 1)
    endwhile
endfunction

" Open a scrollbound split containing on each line the changelist number in
    " which it was last edited.  Accepts a range to limit the section being
    " fully annotated.
function! s:PerforceAnnotate() range
    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom filename . ' not a perforce file'
        return
    endif

    " Use revision specific perforce commands
    let filename = s:PerforceAddHaveRevision(filename)

    " Save the cursor position and buffer number
    let saved_curpos = getcurpos()
    let saved_bufnr = bufnr(bufname("%"))

    " Open a split and perform p4 annotate command
    leftabove vnew
    let perforce_command = 'annotate -q'
    if !g:vp4_annotate_revision
        let perforce_command .= ' -c'
    endif
    let perforce_command .= ' ' . filename . '| cut -d: -f1'
    call s:PerforceRead(perforce_command)
    g/^$/d

    " Perform full annotation
    if !g:vp4_annotate_simple && !g:vp4_annotate_revision
        call s:PerforceAnnotateFull(a:firstline, a:lastline)
    endif

    " Clean up buffer, set local options, move cursor to saved position
    %right
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    setlocal nonumber norelativenumber
    call s:PerforceAnnotateHighlight()
    call setpos('.', saved_curpos)
    set cursorbind scrollbind
    vertical resize 80

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
function! s:PerforceFilelog()
    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom filename . ' not a perforce file'
        return
    endif

    " Set up the command.  Limit the maximum number of entries.
    let command = 'filelog'
    if g:vp4_filelog_max > 0
        let command .= ' ' . '-m ' . g:vp4_filelog_max
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

    " Set up autocommand to get the desired revision when opened.
    augroup test
        autocmd!
        autocmd BufEnter *#* call <SID>PerforceOpenRevision()
    augroup END

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

    let filename = expand('%')
    if !s:PerforceValid(filename)
        echom filename . ' not a perforce file'
        return
    endif

    " Grab the filetype from the original file extension
    let filetype = matchstr(filename, '\.\zs[a-z]\+\ze#')
    execute 'setlocal filetype=' . filetype

    " Print the file to this buffer
    silent call s:PerforceRead('print ' . shellescape(filename, 1))
endfunction

""" Register commands
command! -nargs=? Vp4Diff call <SID>PerforceDiff(<f-args>)
command! -range=% Vp4Annotate <line1>,<line2>call <SID>PerforceAnnotate()
command! Vp4Change call <SID>PerforceChange()
command! Vp4Filelog call <SID>PerforceFilelog()
command! -bang Vp4Revert call <SID>PerforceRevert(<bang>0)
command! Vp4Reopen call <SID>PerforceReopen()
command! Vp4Delete call <SID>PerforceDelete()
command! Vp4Edit call <SID>PerforceEdit()
command! Vp4Add call <SID>PerforceAdd()
command! -bang Vp4Shelve call <SID>PerforceShelve(<bang>0)

augroup PromptOnWrite
    autocmd!
    if g:vp4_prompt_on_write
        autocmd BufWritePre * call <SID>PromptForOpen()
    endif
    if g:vp4_prompt_on_modify
        autocmd FileChangedRO * call <SID>PromptForOpen()
    endif
augroup END
