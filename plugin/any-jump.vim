" TODO:
" - create doc
"
" TODO_THINK:
" - after pressing p jump to next result
" - add auto preview option
" - optimize regexps processing (do most job at first lang?)
" - add failed tests run & move test load to separate command
" - impl VimL rules
"
" TODO_FUTURE_RELEASES:
" - hl keyword line in preview
" - paths priorities for better search results
" - AnyJumpPreview
" - AnyJumpFirst
"
" TODO_MAYBE:
" - add tags file search support (ctags)
" - compact/full ui mode
"
" - jumps history & jumps work flow
" - add "save search" button
" - saved searches list

let s:nvim = has('nvim')

" === Plugin options ===

fu! s:set_plugin_global_option(option_name, default_value) abort
  if !exists('g:' .  a:option_name)
    let g:{a:option_name} = a:default_value
  endif
endfu

" Cursor keyword selection mode
"
" on line:
"
" "MyNamespace::MyClass"
"                  ^
"
" then cursor is on MyClass word
"
" 'word' - will match 'MyClass'
" 'full' - will match 'MyNamespace::MyClass'

call s:set_plugin_global_option('any_jump_keyword_match_cursor_mode', 'word')

" Ungrouped results ui variants:
" - 'filename_first'
" - 'filename_last'
call s:set_plugin_global_option('any_jump_results_ui_style', 'filename_first')

" Show line numbers in search rusults
call s:set_plugin_global_option('any_jump_list_numbers', v:false)

" Auto search usages
call s:set_plugin_global_option('any_jump_usages_enabled', v:true)

" Auto group results by filename
call s:set_plugin_global_option('any_jump_grouping_enabled', v:false)

" Amount of preview lines for each search result
call s:set_plugin_global_option('any_jump_preview_lines_count', 5)

" Max search results, other results can be opened via [a]
call s:set_plugin_global_option('any_jump_max_search_results', 10)

" Prefered search engine: rg or ag
call s:set_plugin_global_option('any_jump_search_prefered_engine', 'rg')

" Disable default keybindinngs for commands
call s:set_plugin_global_option('any_jump_disable_default_keybindings', v:false)

" TODO: NOT_IMPLEMENTED:

" Preview next available search result after pressing preview button
" let g:any_jump_follow_previews = v:true

" ----------------------------------------------
" Functions
" ----------------------------------------------

fu! s:CreateUi(internal_buffer) abort
  if s:nvim
    call s:CreateNvimUi(a:internal_buffer)
  else
    call s:CreateVimUi(a:internal_buffer)
  endif
endfu

fu! s:CreateNvimUi(internal_buffer) abort
  let kw  = a:internal_buffer.keyword
  let buf = bufadd('any-jump lookup ' . kw)

  call setbufvar(buf, '&filetype', 'any-jump')
  call setbufvar(buf, '&bufhidden', 'delete')
  call setbufvar(buf, '&buftype', 'nofile')
  call setbufvar(buf, '&modifiable', 1)

  let height     = float2nr(&lines * 0.6)
  let width      = float2nr(&columns * 0.6)
  let horizontal = float2nr((&columns - width) / 2)
  let vertical   = 2

  let opts = {
        \ 'relative': 'editor',
        \ 'row': vertical,
        \ 'col': horizontal,
        \ 'width': width,
        \ 'height': height
        \ }

  call nvim_open_win(buf, v:true, opts)

  let b:ui = a:internal_buffer

  let a:internal_buffer.vim_bufnr = buf

  call a:internal_buffer.RenderUi()
  call a:internal_buffer.JumpToFirstOfType('link', 'definitions')
endfu

fu! s:CreateVimUi(internal_buffer) abort
  let l:Filter   = function("s:VimPopupFilter")
  let l:Callback = function("s:VimPopupCallback")

  let popup_winid = popup_menu([], {
        \"wrap":       0,
        \"cursorline": 1,
        \"minheight":  20,
        \"maxheight":  30,
        \"minwidth":   90,
        \"maxwidth":   90,
        \"border":     [0,0,0,0],
        \"padding":    [0,1,1,1],
        \"filter":     Filter,
        \"callback":   Callback,
        \})

  " bufwinid

  " let a:internal_buffer.vim_bufnr   = winbufnr(popup_winid)
  let a:internal_buffer.popup_winid = popup_winid
  let a:internal_buffer.vim_bufnr   = winbufnr(popup_winid)

  echo "bufnr -> " . a:internal_buffer.vim_bufnr . '  popup winid -> ' . a:internal_buffer.popup_winid

  " store internal buffer link inside popup window buffer
  " for filter context primarly
  call setbufvar(a:internal_buffer.vim_bufnr, "ui", a:internal_buffer)

  call a:internal_buffer.RenderUi()
endfu

fu! s:VimPopupFilter(popup_winid, key) abort
  let bufnr = winbufnr(a:popup_winid)
  let ib    = getbufvar(bufnr, 'ui')

  if type(ib) != v:t_dict
    return 0
  endif

  echo "filter -> popupwinid-vim: " . a:popup_winid . ' winbufnr' . bufnr

  if a:key == "j" || a:key == "k"
    call popup_filter_menu(a:popup_winid, a:key)
    return 1

  elseif a:key == "p" || a:key == "\<TAB>"
    call g:AnyJumpHandlePreview(ib)
    return 1

  elseif a:key == "a" || a:key == "A"
    call g:AnyJumpToggleAllResults(ib)
    return 1

  elseif a:key == "u" || a:key == "U"
    call g:AnyJumpHandleUsages(ib)
    return 1

  elseif a:key == "T"
    call g:AnyJumpToggleGrouping(ib)
    return 1

  elseif a:key == "\<CR>"
    call popup_filter_menu(a:popup_winid, a:key)
    return 1

  elseif a:key == "q" || a:key == '\<ESC>' ||  a:key == 'Q'
    call g:AnyJumpHandleClose(ib)
    return 1
  endif

  " echo popup_getoptions(b:popup_winid)
  " call popup_close(b:popup_winid)
  return 0
endfu

fu! s:VimPopupCallback(id, result) abort
  echo "id/result -> " . a:id . ' ' . string(a:result)
endfu

" optional:
fu! s:GetCurrentInternalBuffer(...) abort
  " second condition is for empty lists check (a:0 == 1 && a:000 == [[]])
  if a:0 == 0 || (a:0 == 1 && a:1 == [])
    if exists('b:ui')
      let ui = b:ui
    endif
  else
    if type(a:1) == v:t_list
      let ui = a:1[0]
    end
  endif

  if type(ui) == v:t_dict
    return ui
  else
    throw "any-jump InternalBuffer not found"
  endif
endfu

fu! s:Jump() abort
  " check current language
  if !lang_map#lang_exists(&l:filetype)
    call s:log("not found map definition for filetype " . string(&l:filetype))
    return
  endif

  let keyword  = ''

  let cur_mode   = mode()
  let cur_win_id = win_findbuf(bufnr())[0]

  if cur_mode == 'n'
    let keyword = expand('<cword>')
  else
    " THINK: implement visual mode selection?
    " https://stackoverflow.com/a/6271254/190454
    call s:log_debug("not implemented for mode " . cur_mode)
  endif

  if len(keyword) == 0
    return
  endif

  let grep_results = search#SearchDefinitions(&l:filetype, keyword)

  let ib = internal_buffer#GetClass().New()
  let ib.keyword                  = keyword
  let ib.language                 = &l:filetype
  let ib.source_win_id            = cur_win_id
  let ib.grouping_enabled         = g:any_jump_grouping_enabled
  let ib.definitions_grep_results = grep_results

  if g:any_jump_usages_enabled || len(grep_results) == 0
    let ib.usages_opened       = v:true
    let usages_grep_results    = search#SearchUsages(ib)
    let ib.usages_grep_results = usages_grep_results
  endif

  let w:any_jump_last_ib = ib
  call s:CreateUi(ib)
endfu

fu! s:JumpBack() abort
  if exists('w:any_jump_prev_buf_id')
    let new_prev_buf_id = winbufnr(winnr())

    execute ":buf " . w:any_jump_prev_buf_id
    let w:any_jump_prev_buf_id = new_prev_buf_id
  endif
endfu

fu! s:JumpLastResults() abort
  if exists('w:any_jump_last_ib')
    let cur_win_id = win_findbuf(bufnr())[0]
    let w:any_jump_last_ib.source_win_id = cur_win_id

    call s:CreateUi(w:any_jump_last_ib)
  endif
endfu

" ----------------------------------------------
" Event Handlers
" ----------------------------------------------

fu! g:AnyJumpHandleOpen() abort
  if exists('b:ui') && type(b:ui) != v:t_dict
    return
  endif

  let action_item = b:ui.GetItemByPos()
  if type(action_item) != v:t_dict
    return 0
  endif

  " extract link from preview data
  if action_item.type == 'preview_text' && type(action_item.data.link) == v:t_dict
    let action_item = action_item.data.link
  endif

  if action_item.type == 'link'
    if has_key(b:ui, 'source_win_id') && type(b:ui.source_win_id) == v:t_number
      let win_id = b:ui.source_win_id

      " close buffer
      " THINK: TODO: buffer remove options/behaviour?
      close!

      " jump to definition
      call win_gotoid(win_id)

      let buf_id = winbufnr(winnr())
      let w:any_jump_prev_buf_id = buf_id

      execute "edit " . action_item.data.path . '|:' . string(action_item.data.line_number)
    endif
  elseif action_item.type == 'more_button'
    call g:AnyJumpToggleAllResults()
  endif
endfu

fu! g:AnyJumpHandleClose(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  echo "close popup bufnr -> " . ui.vim_bufnr . ' winid ->' . ui.popup_winid

  if s:nvim
    close!
  else
    call popup_close(ui.popup_winid)
  endif
endfu

fu! g:AnyJumpHandleUsages(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  if !has_key(ui, 'keyword') || !has_key(ui, 'language')
    return
  endif

  " close current opened usages
  " TODO: move to method
  if ui.usages_opened
    let ui.usages_opened = v:false

    let idx            = 0
    let layer_start_ln = 0
    let usages_started = v:false

    call ui.StartUiTransaction(bufnr())
    for line in ui.items
      if has_key(line[0], 'data') && type(line[0].data) == v:t_dict
            \ && has_key(line[0].data, 'layer')
            \ && line[0].data.layer == 'usages'

        let line[0].gc = v:true " mark for destroy

        if !layer_start_ln
          let layer_start_ln = idx + 1
          let usages_started = v:true
        endif

        " remove from ui
        call deletebufline(bufnr(), layer_start_ln)

      " remove preview lines for usages
      elseif usages_started && line[0].type == 'preview_text'
        let line[0].gc = v:true
        call deletebufline(bufnr(), layer_start_ln)
      else
        let layer_start_ln = 0
      endif

      let idx += 1
    endfor

    call ui.EndUiTransaction(bufnr())
    call ui.RemoveGarbagedLines()

    call ui.JumpToFirstOfType('link', 'definitions')

    let ui.usages_opened = v:false

    return v:true
  endif

  let grep_results  = search#SearchUsages(ui)
  let filtered      = []

  " filter out results found in definitions
  for result in grep_results
    if index(ui.definitions_grep_results, result) == -1
      " not effective? ( TODO: deletion is more memory effective)
      call add(filtered, result)
    endif
  endfor

  let ui.usages_opened       = v:true
  let ui.usages_grep_results = filtered

  let marker_item = ui.GetFirstItemOfType('help_link')

  let start_ln = ui.GetItemLineNumber(marker_item) - 1

  call ui.StartUiTransaction(bufnr())
  call ui.RenderUiUsagesList(ui.usages_grep_results, start_ln)
  call ui.EndUiTransaction(bufnr())

  call ui.JumpToFirstOfType('link', 'usages')
endfu

fu! g:AnyJumpToFirstLink(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  call ui.JumpToFirstOfType('link')

  return v:true
endfu

fu! g:AnyJumpToggleGrouping(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  let cursor_item = ui.TryFindOriginalLinkFromPos()

  call ui.StartUiTransaction(ui.vim_bufnr)
  call ui.ClearBuffer(ui.vim_bufnr)

  let ui.preview_opened   = v:false
  let ui.grouping_enabled = ui.grouping_enabled ? v:false : v:true

  call ui.RenderUi()
  call ui.EndUiTransaction(ui.vim_bufnr)

  call ui.TryRestoreCursorForItem(cursor_item)
endfu

fu! g:AnyJumpToggleAllResults(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  let ui.overmaxed_results_hidden =
        \ ui.overmaxed_results_hidden ? v:false : v:true

  call ui.StartUiTransaction(ui.vim_bufnr)

  let cursor_item = ui.TryFindOriginalLinkFromPos()

  call ui.ClearBuffer(ui.vim_bufnr)

  let ui.preview_opened = v:false

  call ui.RenderUi()
  call ui.EndUiTransaction(ui.vim_bufnr)

  call ui.TryRestoreCursorForItem(cursor_item)
endfu

fu! g:AnyJumpHandlePreview(...) abort
  let ui = s:GetCurrentInternalBuffer(a:000)

  call ui.StartUiTransaction(ui.vim_bufnr)

  let current_previewed_links = []
  let action_item = ui.GetItemByPos()

  " echo "action item -> " . string(action_item)

  " dispatch to other items handler
  if type(action_item) == v:t_dict && action_item.type == 'more_button'
    call g:AnyJumpToggleAllResults()
    return
  endif

  " remove all previews
  if ui.preview_opened
    let idx            = 0
    let layer_start_ln = 0

    for line in ui.items
      if line[0].type == 'preview_text'
        let line[0].gc = v:true " mark for destroy

        let prev_line = ui.items[idx - 1]

        if type(prev_line[0]) == v:t_dict && prev_line[0].type == 'link'
          call add(current_previewed_links, prev_line[0])
        endif

        if !layer_start_ln
          let layer_start_ln = idx + 1
        endif

        " remove from ui
        call deletebufline(ui.vim_bufnr, layer_start_ln)

      elseif line[0].type == 'help_link'
        " not implemeted
      else
        let layer_start_ln = 0
      endif

      let idx += 1
    endfor

    call ui.RemoveGarbagedLines()
    let ui.preview_opened = v:false
  endif

  " if clicked on just opened preview
  " then just close, not open again
  if index(current_previewed_links, action_item) >= 0
    return
  endif

  if type(action_item) == v:t_dict
    if action_item.type == 'link' && !has_key(action_item.data, "group_header")
      let file_ln               = action_item.data.line_number
      let preview_before_offset = 2
      let preview_after_offset  = g:any_jump_preview_lines_count
      let preview_end_ln        = file_ln + preview_after_offset

      let path = join([getcwd(), action_item.data.path], '/')
      let cmd  = 'head -n ' . string(preview_end_ln) . ' ' . path
            \ . ' | tail -n ' . string(preview_after_offset + 1 + preview_before_offset)

      let preview = split(system(cmd), "\n")

      " TODO: move to func
      let render_ln = ui.GetItemLineNumber(action_item)
      for line in preview
        let new_item = ui.CreateItem("preview_text", line, 0, -1, "Comment", { "link": action_item })
        call ui.AddLineAt([ new_item ], render_ln)

        let render_ln += 1
      endfor

      let ui.preview_opened = v:true
    elseif action_item.type == 'help_link'
      echo "link text"
    endif
  endif

  call ui.EndUiTransaction(ui.vim_bufnr)
endfu


" ----------------------------------------------
" Script & Service functions
" ----------------------------------------------

if !exists('s:debug')
  let s:debug = v:false
endif

fu! s:ToggleDebug()
  let s:debug = s:debug ? v:false : v:true

  echo "debug enabled: " . s:debug
endfu

fu! s:log(message)
  echo "[any-jump] " . a:message
endfu

fu! s:log_debug(message)
  if s:debug == v:true
    echo "[any-jump] " . a:message
  endif
endfu

fu! s:RunSpecs() abort
  let errors = []
  let errors += search#RunSearchEnginesSpecs()
  let errors += search#RunRegexpSpecs()

  if len(errors) > 0
    for error in errors
      echo error
    endfor
  endif

  call s:log("Tests finished")
endfu

" Commands
command! AnyJump call s:Jump()
command! AnyJumpBack call s:JumpBack()
command! AnyJumpLastResults call s:JumpLastResults()
command! AnyJumpRunSpecs call s:RunSpecs()

" KeyBindings
au FileType any-jump nnoremap <buffer> o :call g:AnyJumpHandleOpen()<cr>
au FileType any-jump nnoremap <buffer><CR> :call g:AnyJumpHandleOpen()<cr>
au FileType any-jump nnoremap <buffer> p :call g:AnyJumpHandlePreview()<cr>
au FileType any-jump nnoremap <buffer> <tab> :call g:AnyJumpHandlePreview()<cr>
au FileType any-jump nnoremap <buffer> q :call g:AnyJumpHandleClose()<cr>
au FileType any-jump nnoremap <buffer> <esc> :call g:AnyJumpHandleClose()<cr>
au FileType any-jump nnoremap <buffer> u :call g:AnyJumpHandleUsages()<cr>
au FileType any-jump nnoremap <buffer> U :call g:AnyJumpHandleUsages()<cr>
au FileType any-jump nnoremap <buffer> b :call g:AnyJumpToFirstLink()<cr>
au FileType any-jump nnoremap <buffer> T :call g:AnyJumpToggleGrouping()<cr>
au FileType any-jump nnoremap <buffer> a :call g:AnyJumpToggleAllResults()<cr>
au FileType any-jump nnoremap <buffer> A :call g:AnyJumpToggleAllResults()<cr>

if g:any_jump_disable_default_keybindings == v:false
  nnoremap <leader>j  :AnyJump<CR>
  nnoremap <leader>ab :AnyJumpBack<CR>
  nnoremap <leader>al :AnyJumpLastResults<CR>
end
