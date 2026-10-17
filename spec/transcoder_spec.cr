require "./spec_helper"

# 51 and 63 codepoints, below and above GMP's native base limit of 62
EMOJI_SMALL = "🧳🌂☂️🧵🪡🪢🧶👓🕶🥽🥼🦺👔👕👖🧣🧤🧥🧦👗👘🥻🩴🩱🩲" +
              "🩳👙👚👛👜👝🎒👞👟🥾🥿👠👡🩰👢👑👒🎩🎓🧢⛑🪖💄💍💼"
EMOJI_LARGE = "👋🚆🎠🥖🎏🍇🧳🌂☂️🧵🪡🪢🧶👓🕶🥽🥼🦺👔👕👖🧣🧤🧥🧦👗👘🥻🩴🩱🩲" +
              "🧀🧸🍔🏫🎳🍈🩳👙👚👛👜👝🎒👞👟🥾🥿👠👡🩰👢👑👒🎩🎓🧢⛑🪖💄💍💼"

describe Transcoder do
  describe ".new" do
    it "counts characters, not bytes" do
      Transcoder.new("01").base.should eq 2
      Transcoder.new("🧳🌂").base.should eq 2
      Transcoder.new(EMOJI_SMALL).base.should eq 51 # "☂️" is two codepoints
    end

    it "rejects alphabets with fewer than 2 characters" do
      expect_raises(Multibase::Error, /at least 2/) { Transcoder.new("") }
      expect_raises(Multibase::Error, /at least 2/) { Transcoder.new("a") }
      expect_raises(Multibase::Error, /at least 2/) { Transcoder.new("🧳") }
    end

    it "rejects duplicate characters" do
      expect_raises(Multibase::Error, /duplicate character 'b'/) { Transcoder.new("abcb") }
      expect_raises(Multibase::Error, /duplicate character '🧳'/) { Transcoder.new("🧳🌂🧳") }
    end

    it "rejects alphabets that are not valid UTF-8" do
      expect_raises(Multibase::Error, /valid UTF-8/) { Transcoder.new(String.new(Bytes[0x61, 0xff, 0x62])) }
      expect_raises(Multibase::Error, /valid UTF-8/) { Transcoder.new(String.new(Bytes[0x61, 0xed, 0xa0, 0x80])) }
    end
  end

  describe "#encode" do
    it "keeps leading zero bytes" do
      Transcoder.new("123456789").encode("00000000ffffffff".hexbytes).should eq "111123179768564"
    end

    it "matches hexstrings with the hex alphabet" do
      Transcoder.new("0123456789abcdef").encode("1234abcd".hexbytes).should eq "1234abcd"
    end

    it "encodes with fewer than 62 emojis" do
      Transcoder.new(EMOJI_SMALL).encode("Hello World").should eq "☂🪢👟🩴🩰🥻👚👙🧢🩲🧥🥽🎩👙👝🎒"
    end

    it "encodes with more than 62 emojis" do
      Transcoder.new(EMOJI_LARGE).encode("Hello World").should eq "🍇👚🧤👝👜🕶👑🚆🍔🏫🪢🥽🎒🩴🎠"
    end

    it "encodes integers" do
      decimal = Transcoder.new("0123456789")
      decimal.encode(0).should eq "0"
      decimal.encode(256).should eq "256"
      decimal.encode(UInt64::MAX).should eq UInt64::MAX.to_s
      decimal.encode(UInt128::MAX).should eq UInt128::MAX.to_s
      decimal.encode(BigInt.new(10) ** 100).should eq "1" + "0" * 100
    end

    it "rejects negative integers" do
      expect_raises(Multibase::Error, /negative integer -1/) { Transcoder.new("01").encode(-1) }
      expect_raises(Multibase::Error, /negative/) { Transcoder.new("01").encode(Int64::MIN) }
      expect_raises(Multibase::Error, /negative/) { Transcoder.new("01").encode(-(BigInt.new(10) ** 50)) }
    end
  end

  describe "#decode" do
    it "restores leading zero bytes" do
      Transcoder.new("123456789").decode("111123179768564").should eq "00000000ffffffff".hexbytes
    end

    it "decodes with fewer than 62 emojis" do
      String.new(Transcoder.new(EMOJI_SMALL).decode("☂🪢👟🩴🩰🥻👚👙🧢🩲🧥🥽🎩👙👝🎒")).should eq "Hello World"
    end

    it "decodes with more than 62 emojis" do
      String.new(Transcoder.new(EMOJI_LARGE).decode("🍇👚🧤👝👜🕶👑🚆🍔🏫🪢🥽🎒🩴🎠")).should eq "Hello World"
    end

    it "reports the first invalid character and its position" do
      transcoder = Transcoder.new("0123456789")
      expect_raises(Multibase::Error, "Invalid character 'a' at position 3") { transcoder.decode("123a5b") }
      expect_raises(Multibase::Error, "Invalid character ' ' at position 0") { transcoder.decode(" 1") }
      expect_raises(Multibase::Error, "Invalid character '\\n' at position 1") { transcoder.decode("1\n") }
      expect_raises(Multibase::Error, "Invalid character '\\0' at position 1") { transcoder.decode("1\0") }
      expect_raises(Multibase::Error, "Invalid character '🍕' at position 2") { Transcoder.new(EMOJI_LARGE).decode("👋👋🍕x") }
    end

    it "reports invalid UTF-8 with its byte offset" do
      {Transcoder.new("0123456789"), Transcoder.new(EMOJI_SMALL), Transcoder.new("01\uFFFD")}.each do |transcoder|
        zero = transcoder.alphabet[0].to_s
        input = String.new(zero.to_slice + Bytes[0xff])
        expect_raises(Multibase::Error, "Invalid UTF-8 byte 0xff at byte offset #{zero.bytesize}") { transcoder.decode(input) }
      end
    end

    it "does not mistake invalid UTF-8 for U+FFFD in the alphabet" do
      transcoder = Transcoder.new("ab\uFFFD")
      transcoder.decode("b\uFFFDb").should eq Bytes[16]
      transcoder.decode?(String.new(Bytes[0x61, 0xff, 0x62])).should be_nil
    end
  end

  describe "#decode?" do
    it "returns the bytes of valid input" do
      Transcoder.new("0123456789").decode?("0256").should eq Bytes[0, 1, 0]
      Transcoder.new("0123456789").decode?("").should eq Bytes.empty
    end

    it "returns nil for invalid input" do
      Transcoder.new("0123456789").decode?("12a").should be_nil
      Transcoder.new(EMOJI_LARGE).decode?("👋x").should be_nil
    end
  end

  describe "#decode_int" do
    it "is the inverse of encode(Int)" do
      decimal = Transcoder.new("0123456789")
      decimal.decode_int("0").should eq 0
      decimal.decode_int("256").should eq 256
      decimal.decode_int(UInt128::MAX.to_s).should eq UInt128::MAX
      Transcoder.new(EMOJI_LARGE).decode_int(Transcoder.new(EMOJI_LARGE).encode(123456789)).should eq 123456789
    end

    it "ignores leading zero characters" do
      Transcoder.new("0123456789").decode_int("000256").should eq 256
      Transcoder.new("0123456789").decode_int("000").should eq 0
    end

    it "rejects empty and invalid input" do
      expect_raises(Multibase::Error, /empty string/) { Transcoder.new("01").decode_int("") }
      expect_raises(Multibase::Error, "Invalid character '2' at position 1") { Transcoder.new("01").decode_int("12") }
    end
  end

  describe "#decode_int?" do
    it "returns nil for empty and invalid input" do
      Transcoder.new("01").decode_int?("").should be_nil
      Transcoder.new("01").decode_int?("12").should be_nil
      Transcoder.new("01").decode_int?("110").should eq 6
    end
  end
end

describe Multibase::Error do
  it "is an ArgumentError" do
    expect_raises(ArgumentError) { Base58.decode("0") }
  end
end
