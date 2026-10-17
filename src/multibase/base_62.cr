require "./transcoder"

# Base62 with the alphabet `0-9A-Za-z`, as used by GMP.
#
# ```
# Multibase::Base62.encode("Hello World") # => "73XpUgyMwkGr29M"
# ```
module Multibase::Base62
  extend self

  ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  private TRANSCODER = Transcoder.new(ALPHABET)

  # Encodes *data* to Base62.
  #
  # Strings are encoded as their UTF-8 bytes. Integers must not be negative.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base62 string *str*.
  #
  # Raises `Multibase::Error` on characters outside the alphabet.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end

  # Decodes the Base62 string *str*, or returns `nil` if it is invalid.
  def decode?(str : String) : Bytes?
    TRANSCODER.decode?(str)
  end

  # Decodes the Base62 string *str* into an integer, the inverse of `#encode(Int)`.
  #
  # Leading zero characters are ignored. Raises `Multibase::Error` if *str*
  # is empty or invalid.
  def decode_int(str : String) : BigInt
    TRANSCODER.decode_int(str)
  end

  # Decodes the Base62 string *str* into an integer, or returns `nil` if it is
  # empty or invalid.
  def decode_int?(str : String) : BigInt?
    TRANSCODER.decode_int?(str)
  end
end
