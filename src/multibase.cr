require "./multibase/*"

# Converts bytes and integers to and from Base58, Base62, Base85 and custom
# alphabets (see `Multibase::Transcoder`).
#
# The input is treated as one big number, so this is not compatible with the
# block-based encodings of RFC 4648. Do not use it for Base16, Base32 or
# Base64.
module Multibase
  VERSION = "1.0.0"
end
