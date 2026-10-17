require "./spec_helper"

describe Base85 do
  describe ".encode" do
    it "encodes hello world" do
      Base85.encode("Hello World").should eq "7KPt{PR^XAyM<W"
    end

    it "encodes unicode strings as UTF-8" do
      Base85.encode("Hello, 世界").should eq "%uJ|<6#K5c<7qI0h"
    end

    it "keeps leading zero bytes" do
      Base85.encode("00".hexbytes).should eq "0"
      Base85.encode("00000000ffffffff".hexbytes).should eq "0000|NsC0"
      Base85.encode("ffffffff00000000".hexbytes).should eq "_sw2<`kSC0"
    end
  end

  describe ".decode" do
    it "decodes hello world" do
      String.new(Base85.decode("7KPt{PR^XAyM<W")).should eq "Hello World"
    end

    it "decodes unicode strings" do
      String.new(Base85.decode("%uJ|<6#K5c<7qI0h")).should eq "Hello, 世界"
    end

    it "restores leading zero bytes" do
      Base85.decode("0").should eq "00".hexbytes
      Base85.decode("0000|NsC0").should eq "00000000ffffffff".hexbytes
      Base85.decode("_sw2<`kSC0").should eq "ffffffff00000000".hexbytes
    end
  end

  describe ".encode_ipv6" do
    it "matches the RFC 1924 example" do
      # 1080:0:0:0:8:800:200C:417A
      Base85.encode_ipv6("108000000000000000080800200c417a".hexbytes).should eq "4)+k&C#VzJ4br>0wv%Yp"
    end

    it "always returns 20 characters" do
      Base85.encode_ipv6(Bytes.new(16)).should eq "0" * 20
      Base85.encode_ipv6(("00" * 15 + "01").hexbytes).should eq "00000000000000000001"
      Base85.encode_ipv6(Bytes.new(16, 0xff)).should eq "=r54lj&NUUO~Hi%c2ym0"
    end

    it "accepts a 128-bit integer" do
      Base85.encode_ipv6(0x108000000000000000080800200c417a_u128).should eq "4)+k&C#VzJ4br>0wv%Yp"
      Base85.encode_ipv6(1_u128).should eq "00000000000000000001"
      Base85.encode_ipv6(UInt128::MAX).should eq "=r54lj&NUUO~Hi%c2ym0"
    end

    it "rejects addresses that are not 16 bytes" do
      expect_raises(Multibase::Error, /16 bytes, got 15/) { Base85.encode_ipv6(Bytes.new(15)) }
      expect_raises(Multibase::Error, /16 bytes, got 17/) { Base85.encode_ipv6(Bytes.new(17)) }
      expect_raises(Multibase::Error, /16 bytes, got 0/) { Base85.encode_ipv6(Bytes.empty) }
    end
  end

  describe ".decode_ipv6" do
    it "matches the RFC 1924 example" do
      Base85.decode_ipv6("4)+k&C#VzJ4br>0wv%Yp").should eq "108000000000000000080800200c417a".hexbytes
    end

    it "returns 16 bytes" do
      Base85.decode_ipv6("0" * 20).should eq Bytes.new(16)
      Base85.decode_ipv6("00000000000000000001").should eq ("00" * 15 + "01").hexbytes
      Base85.decode_ipv6("=r54lj&NUUO~Hi%c2ym0").should eq Bytes.new(16, 0xff)
    end

    it "rejects strings that are not 20 characters" do
      expect_raises(Multibase::Error, /20 characters, got 19/) { Base85.decode_ipv6("0" * 19) }
      expect_raises(Multibase::Error, /20 characters, got 21/) { Base85.decode_ipv6("0" * 21) }
      expect_raises(Multibase::Error, /20 characters, got 0/) { Base85.decode_ipv6("") }
    end

    it "rejects values above 128 bits" do
      expect_raises(Multibase::Error, /exceeds 128 bits/) { Base85.decode_ipv6("=r54lj&NUUO~Hi%c2ym1") }
      expect_raises(Multibase::Error, /exceeds 128 bits/) { Base85.decode_ipv6("~" * 20) }
    end

    it "rejects invalid characters" do
      expect_raises(Multibase::Error, /Invalid character ' ' at position 19/) { Base85.decode_ipv6("0" * 19 + " ") }
      expect_raises(Multibase::Error, /Invalid character/) { Base85.decode_ipv6("0" * 19 + "ä") }
    end
  end
end
