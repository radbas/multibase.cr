require "./spec_helper"

# Randomized tests with unusual alphabets and hostile input, checked against
# the naive `ReferenceCodec`.
#
# A failure prints the seed. Reproduce it with `FUZZ_SEED=<seed> crystal spec`,
# run longer with `FUZZ_ITERATIONS=<n>` (default 1).
module Fuzz
  SEED       = ENV.fetch("FUZZ_SEED", "20261017").to_u64
  ITERATIONS = ENV.fetch("FUZZ_ITERATIONS", "1").to_i

  GMP_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # Characters that tend to break parsers: NUL, DEL, the first non-ASCII
  # codepoint, the replacement character, BOM, zero-width space, combining
  # marks, the largest codepoint, an emoji, whitespace and quotes.
  TRICKY = ['\0', '\u007F', '\u0080', '�', '﻿', '​', '́', '️',
            '\u{10FFFF}', '😀', ' ', '\t', '\n', '\r', '"', '\'', '\\']

  # Malformed UTF-8: invalid byte, overlong NUL, lone continuation byte,
  # encoded surrogate, codepoint above U+10FFFF, truncated sequences.
  INVALID_UTF8 = [Bytes[0xff], Bytes[0xc0, 0x80], Bytes[0x80], Bytes[0xed, 0xa0, 0x80],
                  Bytes[0xf4, 0x90, 0x80, 0x80], Bytes[0xf0, 0x9f, 0x98], Bytes[0xe2, 0x82]]

  def self.random_char(random : Random) : Char
    loop do
      code = case random.rand(4)
             when 0 then random.rand(0x80)
             when 1 then random.rand(0x80...0x800)
             when 2 then random.rand(0x800...0x10000)
             else        random.rand(0x10000..0x10FFFF)
             end
      return code.chr unless 0xD800 <= code <= 0xDFFF
    end
  end

  # *size* unique characters of the given *kind*.
  def self.alphabet(random : Random, kind : Symbol, size : Int32) : String
    case kind
    when :gmp
      # identical to GMP's own digits, the fastest path
      (size <= 36 ? GMP_DIGITS.downcase : GMP_DIGITS)[0, size]
    when :ascii
      (0...128).map(&.chr).shuffle!(random).first(size).join
    else
      chars = Set(Char).new
      chars.concat(TRICKY.sample(Math.min(size, 4), random))
      while chars.size < size
        chars << (kind == :mixed && random.rand(2) == 0 ? random.rand(0x80).chr : random_char(random))
      end
      chars.to_a.shuffle(random).join
    end
  end

  def self.alphabets(random : Random) : Array(String)
    alphabets = [] of String
    [2, 10, 16, 36, 37, 58, 62].each { |size| alphabets << alphabet(random, :gmp, size) }
    [2, 3, 7, 36, 61, 62, 63, 64, 85, 94, 127, 128].each { |size| alphabets << alphabet(random, :ascii, size) }
    [2, 3, 47, 62, 63, 100, 256, 300, 1000, 4096, 70_000].each { |size| alphabets << alphabet(random, :unicode, size) }
    [2, 62, 63, 200].each { |size| alphabets << alphabet(random, :mixed, size) }
    (10 * ITERATIONS).times do
      kind = {:gmp, :ascii, :unicode, :mixed}.sample(random)
      max = {gmp: 62, ascii: 128, unicode: 400, mixed: 400}[kind]
      alphabets << alphabet(random, kind, random.rand(2..max))
    end
    alphabets
  end

  def self.payloads(random : Random) : Array(Bytes)
    sizes = [0, 1, 2, 3, 7, 8, 9, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1023, 1024, 1025, 2047, 2048, 2049]
    sizes.concat(Array.new(10 * ITERATIONS) { random.rand(0..2049) })
    payloads = sizes.map { |size| random.random_bytes(size) }
    payloads.concat([Bytes.new(1), Bytes.new(7), Bytes.new(300), Bytes.new(300, 0xff), Bytes[0, 0, 1], Bytes[1, 0, 0]])
    # leading zero bytes in front of random data
    5.times do
      payload = random.random_bytes(random.rand(6..500))
      payload[0, random.rand(1..5)].fill(0_u8)
      payloads << payload
    end
    payloads
  end

  # A random valid string, with a good chance of leading zero characters.
  def self.valid_string(random : Random, chars : Array(Char), max_size : Int32) : String
    String.build do |io|
      random.rand(0..3).times { io << chars[0] } if random.rand(2) == 0
      random.rand(0..max_size).times { io << chars.sample(random) }
    end
  end
end

describe "Fuzzing (seed #{Fuzz::SEED})" do
  random = Random.new(Fuzz::SEED)
  alphabets = Fuzz.alphabets(random)
  payloads = Fuzz.payloads(random)

  it "encodes and decodes exactly like the reference implementation" do
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      reference = ReferenceCodec.new(alphabet)
      payloads.sample(20, random).each do |payload|
        encoded = transcoder.encode(payload)
        encoded.should eq reference.encode(payload)
        transcoder.decode(encoded).should eq payload
        transcoder.decode?(encoded).should eq payload
      end
    end
  end

  it "decodes any valid string, and encoding it again gives the same string" do
    # no two strings decode to the same bytes, so encodings cannot be tampered with
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      reference = ReferenceCodec.new(alphabet)
      (10 * Fuzz::ITERATIONS).times do
        str = Fuzz.valid_string(random, reference.chars, 1000)
        decoded = transcoder.decode(str)
        decoded.should eq reference.decode(str)
        transcoder.encode(decoded).should eq str
        transcoder.decode_int(str).should eq reference.decode_int(str) unless str.empty?
      end
    end
  end

  it "encodes integers like their big-endian bytes" do
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      reference = ReferenceCodec.new(alphabet)
      (5 * Fuzz::ITERATIONS).times do
        bytes = random.random_bytes(random.rand(1..512))
        bytes[0] = 1_u8 if bytes[0] == 0
        int = bytes.reduce(BigInt.new) { |acc, byte| acc * 256 + byte }
        encoded = transcoder.encode(int)
        encoded.should eq reference.encode(bytes)
        transcoder.decode_int(encoded).should eq int
      end
    end
  end

  it "rejects invalid characters with their position" do
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      chars = alphabet.chars
      members = chars.to_set
      (10 * Fuzz::ITERATIONS).times do
        invalid = (Fuzz::TRICKY + Array.new(5) { Fuzz.random_char(random) }).reject { |char| members.includes?(char) }.sample(random)
        prefix = Fuzz.valid_string(random, chars, 50)
        input = prefix + invalid + Fuzz.valid_string(random, chars, 50)

        message = "Invalid character #{invalid.inspect} at position #{prefix.size}"
        expect_raises(Multibase::Error, message) { transcoder.decode(input) }
        expect_raises(Multibase::Error, message) { transcoder.decode_int(input) }
        transcoder.decode?(input).should be_nil
        transcoder.decode_int?(input).should be_nil
      end
    end
  end

  it "rejects malformed UTF-8 with its byte offset" do
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      chars = alphabet.chars
      (10 * Fuzz::ITERATIONS).times do
        prefix = Fuzz.valid_string(random, chars, 50)
        suffix = Fuzz.valid_string(random, chars, 50)
        input = String.new(prefix.to_slice + Fuzz::INVALID_UTF8.sample(random) + suffix.to_slice)

        message = /^Invalid UTF-8 byte 0x[0-9a-f]{2} at byte offset #{prefix.bytesize}$/
        expect_raises(Multibase::Error, message) { transcoder.decode(input) }
        transcoder.decode?(input).should be_nil
        transcoder.decode_int?(input).should be_nil
      end
    end
  end

  it "raises nothing but Multibase::Error on random garbage" do
    alphabets.each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      (10 * Fuzz::ITERATIONS).times do
        input = String.new(random.random_bytes(random.rand(0..200)))
        begin
          decoded = transcoder.decode(input)
        rescue Multibase::Error
          transcoder.decode?(input).should be_nil
        else
          # garbage that happens to be valid must still round-trip
          transcoder.decode?(input).should eq decoded
          transcoder.encode(decoded).should eq input
        end
      end
    end
  end

  it "matches the reference implementation on 8 KB inputs" do
    # deep enough for many levels of divide and conquer
    [Base58::ALPHABET, Base85::ALPHABET, Fuzz.alphabet(random, :unicode, 300), Fuzz.alphabet(random, :unicode, 70_000)].each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      reference = ReferenceCodec.new(alphabet)
      payload = random.random_bytes(8_000)
      encoded = transcoder.encode(payload)
      encoded.should eq reference.encode(payload)
      transcoder.decode(encoded).should eq payload
    end
  end

  it "converts 1 MB in quasi-linear time" do
    # the old digit-by-digit conversion took minutes for Base85
    payload = random.random_bytes(1_000_000)
    [Base58::ALPHABET, Base62::ALPHABET, Base85::ALPHABET, (0x4E00...0x4E00 + 300).map(&.chr).join].each do |alphabet|
      transcoder = Transcoder.new(alphabet)
      elapsed = Time.measure do
        transcoder.decode(transcoder.encode(payload)).should eq payload
      end
      elapsed.should be < 10.seconds
    end
  end
end
