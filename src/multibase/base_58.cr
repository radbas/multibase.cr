require "./transcoder"

# Base58 with the Bitcoin alphabet, which leaves out the lookalikes `0`, `O`,
# `I` and `l`. Compatible with Bitcoin's Base58 (without the Base58Check
# checksum) and the IETF draft "The Base58 Encoding Scheme".
#
# ```
# Multibase::Base58.encode("Hello World") # => "JxF12TrwUP45BMd"
# ```
module Multibase::Base58
  extend self

  ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  private TRANSCODER = Transcoder.new(ALPHABET)

  # Encodes *data* to Base58.
  #
  # Strings are encoded as their UTF-8 bytes. Integers must not be negative.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base58 string *str*.
  #
  # Raises `Multibase::Error` on characters outside the alphabet.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end

  # Decodes the Base58 string *str*, or returns `nil` if it is invalid.
  def decode?(str : String) : Bytes?
    TRANSCODER.decode?(str)
  end

  # Decodes the Base58 string *str* into an integer, the inverse of `#encode(Int)`.
  #
  # Leading zero characters are ignored. Raises `Multibase::Error` if *str*
  # is empty or invalid.
  def decode_int(str : String) : BigInt
    TRANSCODER.decode_int(str)
  end

  # Decodes the Base58 string *str* into an integer, or returns `nil` if it is
  # empty or invalid.
  def decode_int?(str : String) : BigInt?
    TRANSCODER.decode_int?(str)
  end
end
