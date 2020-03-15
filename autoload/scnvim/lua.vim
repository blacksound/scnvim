" File: autoload/scnvim/lua.vim
" Author: David Granström
" Description: Lua interface

autocmd scnvim VimLeavePre * call scnvim#lua#deinit()

function! scnvim#lua#init() abort
  call luaeval('require("scnvim").init()')
endfunction

function! scnvim#lua#deinit() abort
  call luaeval('require("scnvim").deinit()')
endfunction

function! scnvim#lua#help()
  call luaeval('require("scnvim").help.handle_method("", "/Users/dkg/Library/Application Support/SuperCollider/Help/docmap.json")')
  " scnvim.handle_method()
endfunction
