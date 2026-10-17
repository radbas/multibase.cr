require "./spec_helper"
require "json"

describe Base58 do
  it "matches the Bitcoin Core test vectors" do
    # https://github.com/bitcoin/bitcoin/blob/master/src/test/data/base58_encode_decode.json (MIT)
    vectors = Array(Tuple(String, String)).from_json(File.read(File.join(__DIR__, "fixtures", "base58_encode_decode.json")))
    vectors.size.should be > 0
    vectors.each do |hex, encoded|
      Base58.encode(hex.hexbytes).should eq encoded
      Base58.decode(encoded).should eq hex.hexbytes
    end
  end

  it "matches the IETF draft test vectors" do
    # https://datatracker.ietf.org/doc/html/draft-msporny-base58-03#section-5
    Base58.encode("Hello World!").should eq "2NEpo7TZRRrLZSi2U"
    Base58.encode("The quick brown fox jumps over the lazy dog.").should eq "USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z"
    Base58.encode("0000287fb4cd".hexbytes).should eq "11233QC4"
    Base58.decode("11233QC4").should eq "0000287fb4cd".hexbytes
  end

  describe ".encode" do
    it "encodes hello world" do
      Base58.encode("Hello World").should eq "JxF12TrwUP45BMd"
    end

    it "encodes unicode strings as UTF-8" do
      Base58.encode("Hello, 世界").should eq "72k1xXWG5AsuJ7FFns"
    end

    it "keeps leading zero bytes" do
      Base58.encode("00".hexbytes).should eq "1"
      Base58.encode("00000000ffffffff".hexbytes).should eq "11117YXq9G"
      Base58.encode("ffffffff00000000".hexbytes).should eq "jpXCZY5jqM9"
    end
  end

  describe ".decode" do
    it "decodes hello world" do
      String.new(Base58.decode("JxF12TrwUP45BMd")).should eq "Hello World"
    end

    it "decodes unicode strings" do
      String.new(Base58.decode("72k1xXWG5AsuJ7FFns")).should eq "Hello, 世界"
    end

    it "restores leading zero bytes" do
      Base58.decode("1").should eq "00".hexbytes
      Base58.decode("11117YXq9G").should eq "00000000ffffffff".hexbytes
      Base58.decode("jpXCZY5jqM9").should eq "ffffffff00000000".hexbytes
    end

    it "rejects the left out lookalikes" do
      "0OIl".each_char do |char|
        expect_raises(Multibase::Error, /Invalid character '#{char}' at position 1/) { Base58.decode("2#{char}") }
      end
    end
  end
end
