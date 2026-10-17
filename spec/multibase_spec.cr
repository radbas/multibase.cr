require "./spec_helper"
require "yaml"

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
      zero = alphabet[0].to_s

      it "matches a transcoder with the same alphabet" do
        transcoder = Transcoder.new(alphabet)
        random = Random.new(42)
        (0..64).each do |size|
          payload = random.random_bytes(size)
          codec.encode(payload).should eq transcoder.encode(payload)
          codec.decode(codec.encode(payload)).should eq payload
        end
      end

      it "handles empty input" do
        codec.encode("").should eq ""
        codec.encode(Bytes.empty).should eq ""
        codec.decode("").should eq Bytes.empty
        codec.decode?("").should eq Bytes.empty
        codec.decode_int?("").should be_nil
      end

      it "keeps all-zero input" do
        codec.encode(Bytes.new(3)).should eq zero * 3
        codec.decode(zero * 3).should eq Bytes.new(3)
      end

      it "encodes integers like their big-endian bytes" do
        codec.encode(0).should eq zero
        codec.encode(255_u8).should eq codec.encode(Bytes[255])
        codec.encode(UInt64::MAX).should eq codec.encode(Bytes.new(8, 255_u8))
        codec.encode(BigInt.new(2) ** 128).should eq codec.encode(("01" + "00" * 16).hexbytes)
        codec.decode_int(codec.encode(BigInt.new(2) ** 128)).should eq BigInt.new(2) ** 128
      end

      it "raises Multibase::Error on invalid input" do
        expect_raises(Multibase::Error, /negative/) { codec.encode(-1) }
        expect_raises(Multibase::Error, /'"' at position 1/) { codec.decode(%(#{alphabet[1]}"2)) }
        expect_raises(Multibase::Error, /'ä'/) { codec.decode("ä") }
        expect_raises(Multibase::Error, /empty/) { codec.decode_int("") }
        codec.decode?("ä").should be_nil
        codec.decode_int?("ä").should be_nil
      end
    end
  end
end
