require "../spec_helper"

private def annotations(schema : String) : Mcpc::Era::HeaderAnnotations
  Mcpc::Era::HeaderAnnotations.new(JSON.parse(schema))
end

private def mirror(schema : String, arguments : String) : Hash(String, String)
  annotations(schema).mirror(JSON.parse(arguments))
end

private REGION_SCHEMA = %({"type":"object","properties":{
  "region":{"type":"string","x-mcp-header":"Region"},
  "query":{"type":"string"}}})

describe Mcpc::Era::HeaderAnnotations do
  it "mirrors an annotated argument into its header" do
    mirror(REGION_SCHEMA, %({"region":"us-west1","query":"SELECT 1"})).should eq({"Mcp-Param-Region" => "us-west1"})
  end

  it "omits the header when the argument is absent or null" do
    mirror(REGION_SCHEMA, %({"query":"SELECT 1"})).should be_empty
    mirror(REGION_SCHEMA, %({"region":null})).should be_empty
    annotations(REGION_SCHEMA).mirror(nil).should be_empty
  end

  it "encodes values that are unsafe in a header" do
    mirror(REGION_SCHEMA, %({"region":"Hello, 世界"})).should eq({"Mcp-Param-Region" => "=?base64?SGVsbG8sIOS4lueVjA==?="})
  end

  it "writes integers in decimal and booleans in lowercase" do
    schema = %({"type":"object","properties":{
      "limit":{"type":"integer","x-mcp-header":"Limit"},
      "dry":{"type":"boolean","x-mcp-header":"Dry-Run"}}})
    mirror(schema, %({"limit":-7,"dry":true})).should eq({"Mcp-Param-Limit" => "-7", "Mcp-Param-Dry-Run" => "true"})
  end

  it "follows annotations into nested object properties" do
    schema = %({"type":"object","properties":{"target":{"type":"object","properties":{
      "tenant":{"type":"string","x-mcp-header":"Tenant"}}}}})
    mirror(schema, %({"target":{"tenant":"acme"}})).should eq({"Mcp-Param-Tenant" => "acme"})
  end

  it "accepts a schema without annotations" do
    annotations(%({"type":"object","properties":{"q":{"type":"string"}}})).headers_by_path.should be_empty
  end

  it "accepts a property that is itself named x-mcp-header" do
    annotations(%({"type":"object","properties":{"x-mcp-header":{"type":"string"}}})).headers_by_path.should be_empty
  end

  {
    "an empty name"                => %({"type":"object","properties":{"a":{"type":"string","x-mcp-header":""}}}),
    "a name that is no token"      => %({"type":"object","properties":{"a":{"type":"string","x-mcp-header":"Bad Name"}}}),
    "a name with a line feed"      => %({"type":"object","properties":{"a":{"type":"string","x-mcp-header":"A\\nB"}}}),
    "a name that is no string"     => %({"type":"object","properties":{"a":{"type":"string","x-mcp-header":7}}}),
    "a number property"            => %({"type":"object","properties":{"a":{"type":"number","x-mcp-header":"A"}}}),
    "an object property"           => %({"type":"object","properties":{"a":{"type":"object","x-mcp-header":"A"}}}),
    "an untyped property"          => %({"type":"object","properties":{"a":{"x-mcp-header":"A"}}}),
    "names differing only in case" => %({"type":"object","properties":{
      "a":{"type":"string","x-mcp-header":"Region"},"b":{"type":"string","x-mcp-header":"REGION"}}}),
    "an annotation inside array items" => %({"type":"object","properties":{"list":{"type":"array",
      "items":{"type":"object","properties":{"a":{"type":"string","x-mcp-header":"A"}}}}}}),
    "an annotation inside oneOf" => %({"type":"object","oneOf":[
      {"properties":{"a":{"type":"string","x-mcp-header":"A"}}}]}),
  }.each do |fault, schema|
    it "rejects #{fault}" do
      expect_raises(Mcpc::Era::HeaderAnnotations::Invalid) { annotations(schema) }
    end
  end
end
