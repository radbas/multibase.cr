require "./transcoder"

# Base62 using the alphabet `0-9A-Za-z`.
#
# ```
# Multibase::Base62.encode("Hello World") # => "73XpUgyMwkGr29M"
# ```
module Multibase::Base62
  extend self

  ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  private TRANSCODER = Transcoder.new(ALPHABET)

  # Encodes *data* to Base62.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base62 string *str*.
  #
  # Raises `ArgumentError` on invalid characters.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end
end
