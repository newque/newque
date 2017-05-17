#include <string>
#include <cstring>
#include <vector>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/signals.h>

#include "conversions.h"

/* OCaml Option type */
#define Val_none Val_int(0)
value Val_some(value v) {
  CAMLparam1(v);
  CAMLlocal1(some);

  some = caml_alloc(1, 0);
  Store_field(some, 0, v);

  CAMLreturn(some);
}

/*
  std::string -> OCaml string option.
  Empty string = None.
  Supports raw buffers.
*/
value Val_buffer_option(std::string str) {
  CAMLparam0();
  CAMLlocal2(v_ret, v_str);

  if (str == "") {
    v_ret = Val_none;
    CAMLreturn(v_ret);
  }

  char* raw_data = &str[0];
  int data_len = str.length();

  v_str = caml_alloc_string(data_len);
  memcpy(String_val(v_str), raw_data, data_len);
  v_ret = Val_some(v_str);

  CAMLreturn(v_ret);
}

std::vector<std::string> Strings_val_array(value v_strings) {
  CAMLparam1(v_strings);
  CAMLlocal1(v_str);
  int len = Wosize_val(v_strings);
  std::vector<std::string> strings;

  for (int i = 0; i < len; i++) {
    v_str = Field(v_strings, i);
    strings.push_back(std::string(String_val(v_str), caml_string_length(v_str)));
  }

  CAMLreturnT(std::vector<std::string>, strings);
}
