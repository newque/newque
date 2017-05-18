#include <string.h>
#include <stdarg.h>
#include <pthread.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/signals.h>


/* macro from ocaml-lua/stub.h */
#ifndef lua_State_val
#define lua_State_val(L) (*((lua_State **) Data_custom_val(L)))
#endif

extern "C"
value lua_parallel_multi_pcall(value v_L, value v_nargsresults, value v_nmappers)
{
  // Register heap values
  CAMLparam3(v_L, v_nargsresults, v_nmappers);
  CAMLlocal1(v_status);

  // Import values so the lock can be released
  lua_State* L = lua_State_val(v_L);
  int nargsresults = Int_val(v_nargsresults);
  int nmappers = Int_val(v_nmappers);
  int i = 0;
  int status;

  // Release runtime
  caml_enter_blocking_section();

  // Execute all mappers
  for (i = 0; i < nmappers; i++) {
    status = lua_pcall(L, nargsresults, nargsresults, 0);
    if (status != 0) {
      break;
    }
  }

  // Acquire runtime
  caml_leave_blocking_section();

  // Wrap
  v_status = Val_int(status);

  CAMLreturn(v_status);
}
