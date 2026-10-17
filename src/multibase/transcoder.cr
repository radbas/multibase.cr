require "big"

module Multibase
  # :nodoc:
  lib LibGMPExt
    fun gmpz_import = __gmpz_import(rop : LibGMP::MPZ*, count : LibC::SizeT, order : LibC::Int, size : LibC::SizeT, endian : LibC::Int, nails : LibC::SizeT, op : Void*)
    fun gmpz_export = __gmpz_export(rop : Void*, countp : LibC::SizeT*, order : LibC::Int, size : LibC::SizeT, endian : LibC::Int, nails : LibC::SizeT, op : LibGMP::MPZ*) : Void*
  end
end

# Transcodes bytes from and to an arbitrary alphabet.
#
# The alphabet is split into Unicode codepoints (`Char`), so multibyte
# characters like emojis are supported. Leading zero bytes are preserved
# as leading "zero" characters (the first character of the alphabet).
#
# ```
# transcoder = Multibase::Transcoder.new("0123456789")
# transcoder.encode(Bytes[0, 1, 0]) # => "0256"
# transcoder.decode("0256")         # => Bytes[0, 1, 0]
# ```
class Multibase::Transcoder
  # Digits used by GMP for bases up to 36.
  GMP_LOWER = "0123456789abcdefghijklmnopqrstuvwxyz"
  # Digits used by GMP for bases 37 to 62.
  GMP_UPPER = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # The alphabet used for transcoding.
  getter alphabet : String
  # The number of characters in the alphabet.
  getter base : Int32

  @chars : Array(Char)
  # alphabet bytes if the alphabet is ASCII only
  @ascii : Bytes?
  # char to digit lookup, `-1` marks invalid chars
  @ascii_lookup : Array(Int32)?
  @lookup : Hash(Char, Int32) = {} of Char => Int32
  # GMP digit bytes and their reverse lookup (base <= 62 only)
  @gmp_digits : Bytes = Bytes.empty
  @gmp_values : Array(Int32) = [] of Int32
  # alphabet matches GMP's digits, no mapping required
  @identity : Bool = false
  # digits per GMP word and base ** chunk_size (base > 62 only)
  @chunk_size : Int32 = 1
  @chunk_base : UInt64 = 0

  def initialize(@alphabet : String)
    @chars = alphabet.chars
    @base = @chars.size
    raise ArgumentError.new("Alphabet must contain at least 2 characters") if @base < 2

    if alphabet.ascii_only?
      @ascii = alphabet.to_slice
      table = Array(Int32).new(128, -1)
      @chars.each_with_index do |char, i|
        raise ArgumentError.new("Alphabet contains duplicate character #{char.inspect}") if table[char.ord] >= 0
        table[char.ord] = i
      end
      @ascii_lookup = table
    else
      hash = Hash(Char, Int32).new(initial_capacity: @base)
      @chars.each_with_index do |char, i|
        raise ArgumentError.new("Alphabet contains duplicate character #{char.inspect}") if hash.has_key?(char)
        hash[char] = i
      end
      @lookup = hash
    end

    if @base <= 62
      @gmp_digits = (@base <= 36 ? GMP_LOWER : GMP_UPPER).to_slice[0, @base]
      @gmp_values = Array(Int32).new(128, -1)
      @gmp_digits.each_with_index { |b, i| @gmp_values[b] = i }
      @identity = @gmp_digits == alphabet.to_slice
    else
      max = LibGMP::UI::MAX.to_u64
      @chunk_base = @base.to_u64
      while @chunk_base <= max // @base
        @chunk_base *= @base
        @chunk_size += 1
      end
    end
  end

  # Encodes *data* using the alphabet.
  def encode(data : String | Bytes) : String
    data = data.to_slice
    zeros = 0
    while zeros < data.size && data[zeros] == 0
      zeros += 1
    end
    rest = data + zeros
    return render(zeros, Bytes.empty) if rest.empty?

    LibGMP.init(out mpz)
    LibGMPExt.gmpz_import(pointerof(mpz), rest.size, 1, 1, 1, 0, rest.to_unsafe.as(Void*))
    encode_mpz(pointerof(mpz), zeros)
  end

  # Encodes the non-negative integer *int* using the alphabet.
  #
  # Zero is encoded as the first character of the alphabet.
  def encode(int : Int) : String
    raise ArgumentError.new("Cannot encode negative integer #{int}") if int < 0
    return @chars[0].to_s if int == 0

    # copy (mpz = int + 0), the conversion modifies the value in place
    LibGMP.init(out mpz)
    LibGMP.add_ui(pointerof(mpz), int.to_big_i, 0)
    encode_mpz(pointerof(mpz), 0)
  end

  # Decodes *str* into bytes.
  #
  # Raises `ArgumentError` if *str* contains a character that is not part of the alphabet.
  def decode(str : String) : Bytes
    return Bytes.empty if str.empty?

    digits = Array(Int32).new(str.size)
    zeros = 0
    str.each_char_with_index do |char, i|
      digit = digit_of(char)
      raise ArgumentError.new("Invalid character #{char.inspect} at position #{i}") if digit < 0
      zeros += 1 if digit == 0 && zeros == digits.size
      digits << digit
    end
    return Bytes.new(zeros) if zeros == digits.size

    LibGMP.init(out mpz)
    if @base <= 62
      # NUL terminated string of GMP digits
      buf = Bytes.new(digits.size - zeros + 1)
      (zeros...digits.size).each { |i| buf[i - zeros] = @gmp_digits[digits[i]] }
      LibGMP.set_str(pointerof(mpz), buf, @base)
    else
      i = zeros
      while i < digits.size
        len = Math.min(@chunk_size, digits.size - i)
        chunk = 0_u64
        mult = 1_u64
        len.times do
          chunk = chunk * @base + digits[i]
          mult *= @base
          i += 1
        end
        LibGMP.mul_ui(pointerof(mpz), pointerof(mpz), LibGMP::UI.new(mult))
        LibGMP.add_ui(pointerof(mpz), pointerof(mpz), LibGMP::UI.new(chunk))
      end
    end

    size = (LibGMP.sizeinbase(pointerof(mpz), 2).to_i + 7) // 8
    bytes = Bytes.new(zeros + size)
    LibGMPExt.gmpz_export((bytes + zeros).to_unsafe.as(Void*), out _, 1, 1, 1, 0, pointerof(mpz))
    bytes
  end

  # Converts a positive *mpz* into the alphabet, prefixed by *zeros* zero chars.
  # The value of *mpz* is modified.
  private def encode_mpz(mpz : LibGMP::MPZ*, zeros : Int32) : String
    if @base <= 62
      # `sizeinbase` may be 1 greater than the exact value, plus NUL terminator
      buf = Bytes.new(LibGMP.sizeinbase(mpz, @base).to_i + 2)
      LibGMP.get_str(buf, @base, mpz)
      buf = buf[0, buf.index!(0_u8)]
      buf.map! { |b| @gmp_values[b].to_u8 } unless @identity
      return render(zeros, buf, @identity)
    end

    # log2(base) > 5 for base > 62
    digits = Array(Int32).new(LibGMP.sizeinbase(mpz, 2).to_i // 5 + @chunk_size)
    LibGMP.init(out rem)
    while LibGMP.cmp_ui(mpz, 0) != 0
      chunk = LibGMP.tdiv_qr_ui(mpz, pointerof(rem), mpz, LibGMP::UI.new(@chunk_base)).to_u64
      @chunk_size.times do
        digits << (chunk % @base).to_i
        chunk //= @base
      end
    end
    while digits.last? == 0
      digits.pop
    end
    render(zeros, digits.reverse!)
  end

  # Builds the output string from *zeros* zero chars followed by *digits*.
  # If *raw* is set, *digits* already contains the output bytes.
  private def render(zeros : Int32, digits : Indexable(Int), raw : Bool = false) : String
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
      String.build(size * @chars[0].bytesize) do |io|
        zeros.times { io << @chars[0] }
        digits.each { |digit| io << @chars[digit] }
      end
    end
  end

  private def digit_of(char : Char) : Int32
    if table = @ascii_lookup
      char.ascii? ? table[char.ord] : -1
    else
      @lookup.fetch(char, -1)
    end
  end
end
