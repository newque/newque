#include <string>
#include <vector>
#include <caml/mlvalues.h>

#ifndef Val_none
#define Val_none Val_int(0)
#endif

#ifndef CONVERSIONS_H
#define CONVERSIONS_H

value Val_some(value v);

value Val_buffer_option(std::string str);

std::vector<std::string> Strings_val_array(value v_strings);

#endif
