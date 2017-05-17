#include <string>
#include <sstream>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/signals.h>

#include "conversions.h"

std::string register_schema(std::string name, char* raw_schema, size_t length);

bool schema_exists(std::string name);

std::string validate_json(std::string name, char* raw_json, size_t length);


extern "C"
value rj_register_schema(value v_name, value v_raw_schema)
{
  // Register heap values
  CAMLparam2(v_name, v_raw_schema);
  CAMLlocal1(v_ret);

  std::string name(String_val(v_name));
  char* raw_schema = String_val(v_raw_schema);
  size_t length = caml_string_length(v_raw_schema);

  std::string result = register_schema(name, raw_schema, length);

  // Wrap
  v_ret = Val_buffer_option(result);

  CAMLreturn(v_ret);
}

extern "C"
value rj_schema_exists(value v_name)
{
  // Register heap values
  CAMLparam1(v_name);

  std::string name(String_val(v_name));

  bool result = schema_exists(name);

  CAMLreturn(result ? Val_true : Val_false);
}

extern "C"
value rj_validate_json(value v_name, value v_raw_json)
{
  // Register heap values
  CAMLparam2(v_name, v_raw_json);
  CAMLlocal1(v_ret);

  std::string name(String_val(v_name));
  char* raw_json = String_val(v_raw_json);
  size_t length = caml_string_length(v_raw_json);

  // Release runtime
  caml_enter_blocking_section();

  std::string result = validate_json(name, raw_json, length);

  // Acquire runtime
  caml_leave_blocking_section();

  // Wrap
  v_ret = Val_buffer_option(result);

  CAMLreturn(v_ret);
}

extern "C"
value rj_validate_multiple_json(value v_name, value v_raw_jsons)
{
  // Register heap values
  CAMLparam2(v_name, v_raw_jsons);
  CAMLlocal1(v_ret);

  std::string name(String_val(v_name));
  // Makes a copy
  std::vector<std::string> strings = Strings_val_array(v_raw_jsons);

  // Release runtime
  caml_enter_blocking_section();

  std::ostringstream ss;
  for (auto it = strings.begin(); it != strings.end(); ++it) {
    std::string raw_json = *it;
    std::string result = validate_json(name, &raw_json[0], raw_json.length());

    if (result != "") {
      // There's an error
      int position = it - strings.begin();
      if (position != 0) {
        ss << ", ";
      }

      ss << "Index [" << position << "]: " << result;
    }
  }

  // Acquire runtime
  caml_leave_blocking_section();

  // Wrap
  v_ret = Val_buffer_option(ss.str());

  CAMLreturn(v_ret);
}
