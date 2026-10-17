require "./transcoder"

# Base85
#
# RFC 1924
# https://datatracker.ietf.org/doc/html/rfc1924
#
# ```
# Multibase::Base85.encode("Hello World") # => "7KPt{PR^XAyM<W"
# ```
module Multibase::Base85
  extend self

  ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"

  private TRANSCODER = Transcoder.new(ALPHABET)

  # Encodes *data* to Base85.
  def encode(data : String | Bytes | Int) : String
    TRANSCODER.encode(data)
  end

  # Decodes the Base85 string *str*.
  #
  # Raises `ArgumentError` on invalid characters.
  def decode(str : String) : Bytes
    TRANSCODER.decode(str)
  end
end
