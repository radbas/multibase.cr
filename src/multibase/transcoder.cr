require "big"
require "./error"
require "./gmp"

# Transcodes bytes from and to an arbitrary alphabet.
#
# The input is read as one big-endian number and written in the base given by
# the alphabet size, the same way Bitcoin's Base58 works. Leading zero bytes
# are kept as leading "zero" characters (the first character of the alphabet),
# so every byte sequence has exactly one encoding and `#decode` is the exact
# inverse of `#encode`.
#
# The alphabet is split into Unicode codepoints (`Char`), so multibyte
# characters like emojis are supported.
#
# A transcoder is immutable and can be shared between fibers and threads.
#
# ```
# transcoder = Multibase::Transcoder.new("0123456789")
# transcoder.encode(Bytes[0, 1, 0]) # => "0256"
# transcoder.decode("0256")         # => Bytes[0, 1, 0]
# ```
class Multibase::Transcoder
  # Largest base GMP converts natively. Larger bases use divide and conquer.
  private GMP_MAX_BASE = 62
  # GMP's digit characters for bases up to 36 and up to 62.
  private GMP_LOWER = "0123456789abcdefghijklmnopqrstuvwxyz"
  private GMP_UPPER = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  # Machine words converted one by one before switching to divide and conquer.
  private LEAF_WORDS = 128

  # The alphabet used for transcoding.
  getter alphabet : String
  # The number of characters in the alphabet.
  getter base : Int32

  @chars : Array(Char)
  # alphabet bytes, `nil` unless the alphabet is ASCII only
  @ascii : Bytes?
  # digit value of each ASCII character, `-1` if not part of the alphabet
  @ascii_digits : Array(Int32)
  # digit value of each non-ASCII character
  @digits : Hash(Char, Int32)
  @max_char_bytesize : Int32

  # base <= 62: GMP's digit characters, their values, and whether they are
  # identical to the alphabet (no mapping needed)
  @gmp_digits = Bytes.empty
  @gmp_values = Bytes.empty
  @gmp_identity = false

  # base > 62: digits per machine word, `base ** word_digits`, and
  # `base ** leaf_digits`, the largest value converted word by word
  @word_digits = 1
  @word_base = 0_u64
  @leaf_power = BigInt.new(1)

  # Creates a transcoder where each character of *alphabet* stands for its
  # position: the first character is `0`, the second `1` and so on.
  #
  # Raises `Multibase::Error` if *alphabet* has fewer than 2 characters,
  # contains a character twice, or is not valid UTF-8.
  def initialize(@alphabet : String)
    raise Error.new("Alphabet must be valid UTF-8") unless alphabet.valid_encoding?
    @chars = alphabet.chars
    @base = @chars.size
    raise Error.new("Alphabet must contain at least 2 characters") if @base < 2

    @ascii = alphabet.to_slice if alphabet.ascii_only?
    @max_char_bytesize = @chars.max_of(&.bytesize)
    @ascii_digits = Array(Int32).new(128, -1)
    @digits = {} of Char => Int32
    @chars.each_with_index do |char, digit|
      raise Error.new("Alphabet contains duplicate character #{char.inspect}") if digit_of(char) >= 0
      if char.ascii?
        @ascii_digits[char.ord] = digit
      else
        @digits[char] = digit
      end
    end

    if @base <= GMP_MAX_BASE
      @gmp_digits = (@base <= 36 ? GMP_LOWER : GMP_UPPER).to_slice[0, @base]
      @gmp_values = Bytes.new(128)
      @gmp_digits.each_with_index { |byte, digit| @gmp_values[byte] = digit.to_u8 }
      @gmp_identity = @gmp_digits == alphabet.to_slice
    else
      @word_base = @base.to_u64
      while @word_base <= LibGMP::UI::MAX // @base
        @word_base *= @base
        @word_digits += 1
      end
      @leaf_power = BigInt.new(@base) ** leaf_digits
    end
  end

  # Encodes *data* using the alphabet.
  #
  # ```
  # Multibase::Transcoder.new("0123456789").encode(Bytes[1, 0]) # => "256"
  # ```
  def encode(data : String | Bytes) : String
    data = data.to_slice
    zeros = data.index { |byte| byte != 0 } || data.size
    rest = data + zeros
    return render(zeros, Bytes.empty) if rest.empty?

    encode_value(GMP.import(rest), zeros)
  end

  # Encodes the non-negative integer *int* using the alphabet.
  #
  # Zero is encoded as the first character of the alphabet. Raises
  # `Multibase::Error` if *int* is negative.
  #
  # ```
  # Multibase::Transcoder.new("0123456789").encode(256) # => "256"
  # ```
  def encode(int : Int) : String
    raise Error.new("Cannot encode negative integer #{int}") if int < 0
    return @chars[0].to_s if int == 0

    encode_value(int.to_big_i, 0)
  end

  # Decodes *str* into bytes.
  #
  # Raises `Multibase::Error` if *str* contains a character that is not part
  # of the alphabet or is not valid UTF-8. Nothing is skipped, not even
  # whitespace.
  #
  # ```
  # Multibase::Transcoder.new("0123456789").decode("256") # => Bytes[1, 0]
  # ```
  def decode(str : String) : Bytes
    decode?(str) || raise invalid_input(str)
  end

  # Like `#decode`, but returns `nil` if *str* is invalid.
  def decode?(str : String) : Bytes?
    if parsed = parse(str)
      zeros, value = parsed
      GMP.export(value, zeros + GMP.byte_size(value))
    end
  end

  # Decodes *str* into a non-negative integer, the inverse of `#encode(Int)`.
  #
  # Leading zero characters are ignored, so zero-padded strings decode to the
  # same number. Raises `Multibase::Error` if *str* is empty or invalid.
  #
  # ```
  # Multibase::Transcoder.new("0123456789").decode_int("00256") # => 256
  # ```
  def decode_int(str : String) : BigInt
    raise Error.new("Cannot decode empty string to integer") if str.empty?
    decode_int?(str) || raise invalid_input(str)
  end

  # Like `#decode_int`, but returns `nil` if *str* is empty or invalid.
  def decode_int?(str : String) : BigInt?
    return if str.empty?
    parse(str).try &.[1]
  end

  # Splits *str* into the number of leading zero characters and the value of
  # the remaining digits. Returns `nil` if *str* is invalid.
  private def parse(str : String) : {Int32, BigInt}?
    if @base <= GMP_MAX_BASE
      # GMP digits, NUL terminated for `set_str`
      digits = Bytes.new(str.bytesize + 1)
      size = 0
      valid = each_digit(str) do |digit|
        digits[size] = @gmp_digits[digit]
        size += 1
      end
      return unless valid

      zeros = digits.index! { |byte| byte != '0'.ord }
      return {zeros, BigInt.new} if zeros == size
      {zeros, BigInt.new { |mpz| LibGMP.set_str(mpz, digits + zeros, @base) }}
    else
      digits = Array(Int32).new(str.size)
      return unless each_digit(str) { |digit| digits << digit }

      zeros = digits.index { |digit| digit != 0 } || digits.size
      {zeros, digits_to_big(digits, zeros)}
    end
  end

  # Yields the digit value of each character of *str*. Returns `false` if a
  # character is not part of the alphabet or *str* is not valid UTF-8.
  private def each_digit(str : String, & : Int32 ->) : Bool
    if @ascii
      # any byte >= 0x80, including malformed UTF-8, is invalid
      str.to_slice.each do |byte|
        digit = byte < 0x80 ? @ascii_digits[byte] : -1
        return false if digit < 0
        yield digit
      end
    else
      return false unless str.valid_encoding?
      str.each_char do |char|
        digit = digit_of(char)
        return false if digit < 0
        yield digit
      end
    end
    true
  end

  # Describes the first problem in *str*, which `#parse` rejected.
  private def invalid_input(str : String) : Error
    reader = Char::Reader.new(str)
    index = 0
    while reader.has_next?
      if byte = reader.error
        return Error.new("Invalid UTF-8 byte 0x#{"%02x" % byte} at byte offset #{reader.pos}")
      end
      char = reader.current_char
      return Error.new("Invalid character #{char.inspect} at position #{index}") if digit_of(char) < 0
      reader.next_char
      index += 1
    end
    Error.new("Invalid input")
  end

  private def digit_of(char : Char) : Int32
    char.ascii? ? @ascii_digits[char.ord] : @digits.fetch(char, -1)
  end

  # Encodes the positive *value*, prefixed by *zeros* zero characters.
  private def encode_value(value : BigInt, zeros : Int32) : String
    check_output_size(value, zeros)
    if @base <= GMP_MAX_BASE
      render(zeros, gmp_digits(value), raw: @gmp_identity)
    else
      render(zeros, big_to_digits(value))
    end
  end

  # Raises if the encoding of *value* would exceed the maximum `String` size.
  private def check_output_size(value : BigInt, zeros : Int32) : Nil
    digits = LibGMP.sizeinbase(value, 2) / Math.log2(@base) + 1
    if (zeros + digits) * @max_char_bytesize > Int32::MAX
      raise Error.new("Encoded output would exceed the maximum string size")
    end
  end

  # Converts *value* with GMP (base <= 62). Returns GMP's digit characters if
  # they are identical to the alphabet, digit values otherwise.
  private def gmp_digits(value : BigInt) : Bytes
    # `sizeinbase` may be 1 too large, plus NUL terminator
    buf = Bytes.new(LibGMP.sizeinbase(value, @base).to_i + 2)
    LibGMP.get_str(buf, @base, value)
    buf = buf[0, buf.index!(0_u8)]
    buf.map! { |byte| @gmp_values[byte] } unless @gmp_identity
    buf
  end

  # Number of digits in `@leaf_power`.
  private def leaf_digits : Int32
    @word_digits * LEAF_WORDS
  end

  # Converts *digits* (most significant first) from index *start* to a number.
  #
  # Splits the digits into leaves of `leaf_digits`, converts each one word by
  # word, then merges neighbours pairwise (`high * base ** n + low`), doubling
  # `n` every round. With GMP's fast multiplication this runs in quasi-linear
  # time, unlike the quadratic digit-by-digit loop.
  private def digits_to_big(digits : Array(Int32), start : Int32) : BigInt
    count = digits.size - start
    return BigInt.new if count == 0

    # right aligned, so only the first leaf can be shorter
    first = (count - 1) % leaf_digits + 1
    level = [leaf_to_big(digits, start, first)]
    (start + first).step(to: digits.size - 1, by: leaf_digits) do |i|
      level << leaf_to_big(digits, i, leaf_digits)
    end

    power = @leaf_power
    while level.size > 1
      # pair from the right, so every low half has as many digits as `power`
      merged = Array(BigInt).new((level.size + 1) // 2)
      merged << level.first if level.size.odd?
      (level.size % 2).step(to: level.size - 2, by: 2) do |i|
        merged << level[i] * power + level[i + 1]
      end
      level = merged
      power *= power if level.size > 1
    end
    level.first
  end

  # Converts *size* digits starting at *from* to a number, one word at a time.
  private def leaf_to_big(digits : Array(Int32), from : Int32, size : Int32) : BigInt
    BigInt.new do |mpz|
      i = from
      stop = from + size
      while i < stop
        word = 0_u64
        scale = 1_u64
        Math.min(@word_digits, stop - i).times do
          word = word * @base + digits[i]
          scale *= @base
          i += 1
        end
        LibGMP.mul_ui(mpz, mpz, LibGMP::UI.new(scale))
        LibGMP.add_ui(mpz, mpz, LibGMP::UI.new(word))
      end
    end
  end

  # Converts the positive *value* to digits, most significant first.
  #
  # The inverse of `#digits_to_big`: splits *value* recursively by
  # `base ** (leaf_digits * 2 ** k)` until the parts fit into a leaf.
  private def big_to_digits(value : BigInt) : Array(Int32)
    # powers[k] = @leaf_power ** (2 ** k), up to the largest not above value
    powers = [] of BigInt
    power = @leaf_power
    while power <= value
      powers << power
      # skip the last squaring if the result would surely exceed value
      break if 2 * (power.bit_length - 1) >= value.bit_length
      power *= power
    end

    digits = Array(Int32).new((value.bit_length / Math.log2(@base)).to_i + 1)
    append_digits(digits, value, powers, powers.size - 1, pad: false)
    digits
  end

  # Appends the digits of *value*, which is less than `powers[level] ** 2`
  # (`@leaf_power` if *level* is `-1`). With *pad*, appends exactly
  # `leaf_digits * 2 ** (level + 1)` digits, left padded with zeros.
  private def append_digits(digits : Array(Int32), value : BigInt, powers : Array(BigInt), level : Int32, pad : Bool) : Nil
    return append_leaf(digits, value, pad) if level < 0

    high, low = value.divmod(powers[level])
    if pad || high > 0
      append_digits(digits, high, powers, level - 1, pad)
      append_digits(digits, low, powers, level - 1, pad: true)
    else
      append_digits(digits, low, powers, level - 1, pad: false)
    end
  end

  # Appends the digits of *value*, which is less than `@leaf_power`, one word
  # at a time. With *pad*, appends exactly `leaf_digits` digits.
  private def append_leaf(digits : Array(Int32), value : BigInt, pad : Bool) : Nil
    # split into words, least significant first, dividing a copy in place
    words = StaticArray(UInt64, LEAF_WORDS).new(0_u64)
    count = 0
    LibGMP.init(out rest)
    LibGMP.init(out remainder)               # unused, but required by `tdiv_qr_ui`
    LibGMP.add_ui(pointerof(rest), value, 0) # rest = value
    while count < LEAF_WORDS && (pad || LibGMP.cmp_ui(pointerof(rest), 0) != 0)
      words[count] = LibGMP.tdiv_qr_ui(pointerof(rest), pointerof(remainder), pointerof(rest), LibGMP::UI.new(@word_base)).to_u64
      count += 1
    end

    # only the most significant word may go without leading zeros
    (count - 1).downto(0) do |i|
      append_word(digits, words[i], pad: pad || i < count - 1)
    end
  end

  # Appends the digits of *word*. With *pad*, appends exactly `@word_digits`
  # digits, otherwise none for zero.
  private def append_word(digits : Array(Int32), word : UInt64, pad : Bool) : Nil
    # least significant first; base > 62 means at most 10 digits per word
    buffer = StaticArray(Int32, 16).new(0)
    size = 0
    while word > 0 || (pad && size < @word_digits)
      buffer[size] = (word % @base).to_i
      word //= @base
      size += 1
    end
    (size - 1).downto(0) { |i| digits << buffer[i] }
  end

  # Builds the output from *zeros* zero characters followed by *digits*. With
  # *raw*, *digits* already holds the output bytes.
  private def render(zeros : Int32, digits : Bytes | Array(Int32), raw : Bool = false) : String
    size = zeros + digits.size
    if ascii = @ascii
      String.new(size) do |buf|
        Slice.new(buf, zeros).fill(ascii[0])
        if raw && digits.is_a?(Bytes)
          digits.copy_to(buf + zeros, digits.size)
        else
          digits.each_with_index { |digit, i| buf[zeros + i] = ascii[digit] }
        end
        {size, size}
      end
    else
      String.build(size * @max_char_bytesize) do |io|
        zeros.times { io << @chars[0] }
        digits.each { |digit| io << @chars[digit] }
      end
    end
  end
end
