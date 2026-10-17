require "./multibase/*"

# Convert bytes between multiple bases using custom alphabets.
#
# Not compatible with RFC 4648 - do not use for Base16, Base32 or Base64.
# https://www.rfc-editor.org/rfc/rfc4648
module Multibase
  VERSION = "0.2.0"
end
