#include <string>
#include <sstream>
#include <unordered_map>

#include "rapidjson/document.h"
#include "rapidjson/schema.h"
#include "rapidjson/writer.h"
#include "rapidjson/stringbuffer.h"
#include "rapidjson/error/en.h"

using namespace rapidjson;

std::unordered_map<std::string, SchemaDocument* > schemas;

std::string get_parse_error(Document* doc) {
  std::ostringstream ss;

  ss << "JSON Parsing Error at character "
    << (unsigned)doc->GetErrorOffset() << ": "
    << GetParseError_En(doc->GetParseError());

  return ss.str();
}

std::string register_schema(std::string name, char* raw_schema, size_t length) {
  Document doc;

  if (doc.Parse(raw_schema, length).HasParseError()) {
    return get_parse_error(&doc);
  }

  if (schemas.count(name) == 1) {
    std::ostringstream ss;
    ss << "A schema of the name [" << name << "] already exists";
    return ss.str();
  }

  // Never freed
  schemas[name] = new SchemaDocument(doc);

  return "";
}

bool schema_exists(std::string name) {
  return schemas.count(name) == 1;
}

std::string validate_json(std::string name, char* raw_json, size_t length) {
  Document doc_schema;
  Document doc_json;
  std::ostringstream ss;

  if (doc_json.Parse(raw_json, length).HasParseError()) {
    ss << get_parse_error(&doc_json);
    return ss.str();
  }

  if (schemas.count(name) == 0) {
    ss << "Schema [" << name << "] does not exist";
    return ss.str();
  }

  SchemaDocument &schema = *(schemas[name]);
  SchemaValidator validator(schema);

  if (!doc_json.Accept(validator)) {
    StringBuffer sb1;
    StringBuffer sb2;

    validator.GetInvalidDocumentPointer().StringifyUriFragment(sb1);
    validator.GetInvalidSchemaPointer().StringifyUriFragment(sb2);

    ss
      << "JSON Validation Failure: ["
      << validator.GetInvalidSchemaKeyword()
      << "] at ["
      << sb1.GetString()
      << "] conflicts with the schema ["
      << name
      << "] at ["
      << sb2.GetString()
      << "]";

    return ss.str();
  }

  return "";
}
