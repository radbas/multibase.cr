require "./transcoder"

# Base85 with the alphabet of RFC 1924.
#
# `#encode` and `#decode` work on input of any length, like the other
# encodings in this library. RFC 1924 itself only defines a fixed-width
# encoding of 128-bit IPv6 addresses, which `#encode_ipv6` and `#decode_ipv6`
# implement.
#
# https://datatracker.ietf.org/doc/html/rfc1924
#
# ```
# Multibase::Base85.encode("Hello World") # => "7KPt{PR^XAyM<W"
# ```
module Multibase::Base85
  extend self

  ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"

  private TRANSCODER = Transcoder.new(ALPHABET)
  # RFC 1924 addresses are always 20 characters long
  private IPV6_SIZE = 20

  # Encodes *data* to Base85.
  #
  # Strings are encoded as their UTF-8 bytes. Integers must not be negative.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base85 string *str*.
  #
  # Raises `Multibase::Error` on characters outside the alphabet.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end

  # Decodes the Base85 string *str*, or returns `nil` if it is invalid.
  def decode?(str : String) : Bytes?
    TRANSCODER.decode?(str)
  end

  # Decodes the Base85 string *str* into an integer, the inverse of `#encode(Int)`.
  #
  # Leading zero characters are ignored. Raises `Multibase::Error` if *str*
  # is empty or invalid.
  def decode_int(str : String) : BigInt
    TRANSCODER.decode_int(str)
  end

  # Decodes the Base85 string *str* into an integer, or returns `nil` if it is
  # empty or invalid.
  def decode_int?(str : String) : BigInt?
    TRANSCODER.decode_int?(str)
  end

  # Encodes a 16-byte IPv6 *address* as specified by RFC 1924: always 20
  # characters, left padded with `'0'`.
  #
  # Raises `Multibase::Error` if *address* is not 16 bytes long.
  #
  # ```
  # address = "108000000000000000080800200c417a".hexbytes # 1080::8:800:200C:417A
  # Multibase::Base85.encode_ipv6(address)                # => "4)+k&C#VzJ4br>0wv%Yp"
  # ```
  def encode_ipv6(address : Bytes) : String
    raise Error.new("IPv6 address must be 16 bytes, got #{address.size}") unless address.size == 16
    pad_ipv6(TRANSCODER.encode(GMP.import(address)))
  end

  # Encodes the IPv6 *address* given as a 128-bit integer as specified by
  # RFC 1924.
  #
  # ```
  # Multibase::Base85.encode_ipv6(1_u128) # => "00000000000000000001"
  # ```
  def encode_ipv6(address : UInt128) : String
    pad_ipv6(TRANSCODER.encode(address))
  end

  # Decodes an RFC 1924 IPv6 address into its 16 bytes.
  #
  # Raises `Multibase::Error` unless *str* is exactly 20 valid characters
  # representing a value below `2 ** 128`.
  def decode_ipv6(str : String) : Bytes
    raise Error.new("RFC 1924 IPv6 address must be #{IPV6_SIZE} characters, got #{str.size}") unless str.size == IPV6_SIZE
    value = TRANSCODER.decode_int(str)
    raise Error.new("RFC 1924 IPv6 address exceeds 128 bits") if GMP.byte_size(value) > 16
    GMP.export(value, 16)
  end

  private def pad_ipv6(encoded : String) : String
    encoded.rjust(IPV6_SIZE, ALPHABET[0])
  end
end
