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
"   - file not under client root
"   - file under root but not on client
"   - file on client and not opened for edit

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
function! s:PerforceDiff()
    " Get the file name and revision
    let filename = expand('%')
    if !s:PerforceValidAndOpen(filename)
        echom filename . ' not perforce file opened for edit'
        return
    endif
    let filename = s:PerforceAddHaveRevision(filename)
    let filetype = &filetype

    " Setup current window
    diffthis

    " Setup non modifiable buffer for perforce
    rightbelow vnew
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
    let perforce_command = 'print ' . filename
    silent call s:PerforceRead(perforce_command)
    setlocal nomodifiable
    execute "set filetype=" . filetype
    diffthis

    " q to exit
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

" Call p4 revert.  Confirms before performing the revert.
function! s:PerforceRevert(bang)
    let filename = expand('%')
    if !s:PerforceValidAndOpen(filename)
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
    let filename = expand('%')
    if !s:PerforceValidAndOpen(filename)
        echom 'not a perforce file opened for edit'
        return
    endif

    topleft new __perforce_change__
    normal! ggdG

    " If this file is already in a changelist, allow the user to modify that
    " changelist by calling `p4 change -o <cl#>`.  Otherwise, call for default
    " changelist.
    let perforce_command = 'change -o'
    let lnr = 26
    let changelist = s:PerforceSystem('fstat ' . filename
            \ . ' | grep change | cut -d " " -f3')
    if changelist
        let perforce_command .= ' ' . changelist
        let lnr = 28
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
    if !s:PerforceValidAndOpen(filename)
        echom 'not a perforce file opened for edit'
        return
    endif

    " Get the pending changes in the current client
    let perforce_command = "changes -u $USER -s pending -c $P4CLIENT"
    let changes = split(s:PerforceSystem(perforce_command), '\n')

    " Prepend with choice numbers, starting at 1
    call map(changes, 'v:key + 1 . ". " . v:val')

    " Prompt the user
    let currentchangelist = split(s:PerforceSystem('fstat ' . filename
            \ . ' | grep change | cut -d " " -f3'), '\n')[0]
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

""" Register commands
command! Vp4Diff call <SID>PerforceDiff()
command! -range=% Vp4Annotate <line1>,<line2>call <SID>PerforceAnnotate()
command! Vp4Change call <SID>PerforceChange()
command! -bang Vp4Revert call <SID>PerforceRevert(<bang>0)
command! Vp4Reopen call <SID>PerforceReopen()
command! Vp4Edit call <SID>PerforceEdit()

augroup PromptOnWrite
    autocmd!
    if g:vp4_prompt_on_write
        autocmd BufWritePre * call <SID>PromptForOpen()
    endif
    if g:vp4_prompt_on_modify
        autocmd FileChangedRO * call <SID>PromptForOpen()
    endif
augroup END
