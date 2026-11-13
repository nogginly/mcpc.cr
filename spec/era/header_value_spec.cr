require "../spec_helper"

describe MCPC::Era::HeaderValue do
  # The encoding examples of the 2026-07-28 Streamable HTTP specification.
  {
    "us-west1"           => "us-west1",
    "Hello, 世界"          => "=?base64?SGVsbG8sIOS4lueVjA==?=",
    " padded "           => "=?base64?IHBhZGRlZCA=?=",
    "line1\nline2"       => "=?base64?bGluZTEKbGluZTI=?=",
    "=?base64?literal?=" => "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=",
    "two words"          => "two words",
    "file:///a/b.json"   => "file:///a/b.json",
  }.each do |original, encoded|
    it "encodes #{original.inspect} as #{encoded}" do
      MCPC::Era::HeaderValue.encode(original).should eq(encoded)
    end
  end
end
