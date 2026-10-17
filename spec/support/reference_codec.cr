require "big"

# A deliberately naive transcoder that is obviously correct: the specs compare
# the optimized `Multibase::Transcoder` against it.
struct ReferenceCodec
  getter chars : Array(Char)

  def initialize(alphabet : String)
    @chars = alphabet.chars
    @digits = {} of Char => Int32
    @chars.each_with_index { |char, digit| @digits[char] = digit }
  end

  def encode(data : Bytes) : String
    zeros = data.index { |byte| byte != 0 } || data.size
    value = data.reduce(BigInt.new) { |acc, byte| acc * 256 + byte }
    digits = [] of Char
    while value > 0
      value, digit = value.divmod(@chars.size)
      digits << @chars[digit.to_i]
    end
    @chars[0].to_s * zeros + digits.reverse.join
  end

  def decode(str : String) : Bytes
    chars = str.chars
    zeros = chars.index { |char| char != @chars[0] } || chars.size
    value = decode_int(str)
    bytes = [] of UInt8
    while value > 0
      value, byte = value.divmod(256)
      bytes << byte.to_u8
    end
    bytes.concat(Array.new(zeros, 0_u8)).reverse!
    Bytes.new(bytes.size) { |i| bytes[i] }
  end

  def decode_int(str : String) : BigInt
    str.each_char.reduce(BigInt.new) { |acc, char| acc * @chars.size + @digits[char] }
  end
end
