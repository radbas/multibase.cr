require "./spec_helper"
require "yaml"

ALPHABETS = {
  "binary"  => "01",
  "decimal" => "0123456789",
  "hex"     => "0123456789abcdef",
  "base36"  => "0123456789abcdefghijklmnopqrstuvwxyz",
  "base62"  => Base62::ALPHABET,
  "base63"  => Base62::ALPHABET + "_",
  "base85"  => Base85::ALPHABET,
  "cjk300"  => (0...300).map { |i| (0x4E00 + i).chr }.join,
  "emoji"   => "🧳🌂🧵🪡🪢🧶👓🕶🥽🥼🦺👔👕👖🧣🧤🧥🧦👗👘🥻🩴🩱🩲🩳👙👚👛👜👝🎒👞👟🥾🥿👠👡🩰👢👑👒🎩🎓🧢⛑🪖💄💍💼",
}

def random_payloads
  random = Random.new(42)
  payloads = (0..64).map { |size| random.random_bytes(size) }
  payloads << Bytes.new(5)
  payloads << Bytes[0, 0, 1, 0]
  payloads << "a9eb5d".hexbytes
  payloads
end

describe Multibase do
  it "has the shard.yml version" do
    shard = YAML.parse(File.read(File.join(__DIR__, "..", "shard.yml")))
    Multibase::VERSION.should eq shard["version"].as_s
  end

  {
    {"Base58", Base58, Base58::ALPHABET},
    {"Base62", Base62, Base62::ALPHABET},
    {"Base85", Base85, Base85::ALPHABET},
  }.each do |name, codec, alphabet|
    describe name do
      it "round-trips random bytes" do
        random_payloads.each do |payload|
          encoded = codec.encode(payload)
          encoded.should_not contain('\0')
          codec.decode(encoded).should eq payload
        end
      end

      it "handles empty input" do
        codec.encode("").should eq ""
        codec.encode(Bytes.empty).should eq ""
        codec.decode("").should eq Bytes.empty
      end

      it "preserves all-zero input" do
        zero = alphabet[0].to_s
        codec.encode(Bytes.new(3)).should eq zero * 3
        codec.decode(zero * 3).should eq Bytes.new(3)
      end

      it "encodes integers" do
        zero = alphabet[0].to_s
        codec.encode(0).should eq zero
        codec.encode(255_u8).should eq codec.encode(Bytes[255])
        codec.encode(UInt64::MAX).should eq codec.encode(Bytes.new(8, 255_u8))
        codec.encode(BigInt.new(2) ** 128).should eq codec.encode(("01" + "00" * 16).hexbytes)
      end

      it "raises on negative integers" do
        expect_raises(ArgumentError, /negative/) { codec.encode(-1) }
      end

      it "raises on invalid characters" do
        expect_raises(ArgumentError, /'"' at position 1/) { codec.decode(%(1"2)) }
        expect_raises(ArgumentError, /'ä'/) { codec.decode("ä") }
      end
    end
  end

  describe "Base58" do
    it "matches the bitcoin test vectors" do
      {
        ""                                                   => "",
        "61"                                                 => "2g",
        "626262"                                             => "a3gV",
        "636363"                                             => "aPEr",
        "73696d706c792061206c6f6e6720737472696e67"           => "2cFupjhnEsSn59qHXstmK2ffpLv2",
        "00eb15231dfceb60925886b67d065299925915aeb172c06647" => "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L",
        "516b6fcd0f"                                         => "ABnLTmg",
        "bf4f89001e670274dd"                                 => "3SEo3LWLoPntC",
        "572e4794"                                           => "3EFU7m",
        "ecac89cad93923c02321"                               => "EJDM8drfXA6uyA",
        "10c8511e"                                           => "Rt5zm",
        "00000000000000000000"                               => "1111111111",
      }.each do |hex, encoded|
        Base58.encode(hex.hexbytes).should eq encoded
        Base58.decode(encoded).should eq hex.hexbytes
      end
    end
  end

  describe Transcoder do
    ALPHABETS.each do |name, alphabet|
      it "round-trips random bytes with #{name} alphabet" do
        transcoder = Transcoder.new(alphabet)
        transcoder.base.should eq alphabet.size
        random_payloads.each do |payload|
          encoded = transcoder.encode(payload)
          encoded.each_char { |char| alphabet.should contain(char) }
          transcoder.decode(encoded).should eq payload
        end
      end
    end

    it "matches Base62 with the Base62 alphabet" do
      transcoder = Transcoder.new(Base62::ALPHABET)
      random_payloads.each do |payload|
        transcoder.encode(payload).should eq Base62.encode(payload)
      end
    end

    it "matches hexstring with the hex alphabet" do
      transcoder = Transcoder.new("0123456789abcdef")
      transcoder.encode("1234abcd".hexbytes).should eq "1234abcd"
    end

    it "raises on too short alphabets" do
      expect_raises(ArgumentError, /at least 2/) { Transcoder.new("") }
      expect_raises(ArgumentError, /at least 2/) { Transcoder.new("🧳") }
    end

    it "raises on duplicate characters" do
      expect_raises(ArgumentError, /duplicate character 'b'/) { Transcoder.new("abcb") }
      expect_raises(ArgumentError, /duplicate character '🧳'/) { Transcoder.new("🧳🌂🧳") }
    end
  end
end
