require "./transcoder"

# Base58 using the Bitcoin alphabet.
#
# ```
# Multibase::Base58.encode("Hello World") # => "JxF12TrwUP45BMd"
# ```
module Multibase::Base58
  extend self

  ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  private TRANSCODER = Transcoder.new(ALPHABET)

  # Encodes *data* to Base58.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base58 string *str*.
  #
  # Raises `ArgumentError` on invalid characters.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end
end
