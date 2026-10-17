require "./spec_helper"
require "openssl/md5"

describe Base62 do
  describe ".encode" do
    it "encodes hello world" do
      Base62.encode("Hello World").should eq "73XpUgyMwkGr29M"
    end

    it "encodes unicode strings as UTF-8" do
      Base62.encode("Hello, 世界").should eq "1wJfrzvdbuFbL65vcS"
    end

    it "keeps leading zero bytes" do
      Base62.encode("00".hexbytes).should eq "0"
      Base62.encode("00000000ffffffff".hexbytes).should eq "00004gfFC3"
      Base62.encode("ffffffff00000000".hexbytes).should eq "LygHZwPV2MC"
    end

    it "encodes an md5 hash" do
      Base62.encode(OpenSSL::MD5.hash("Hello World").to_slice).should eq "5O4SoozqXEOwlYtvkC5zkr"
    end

    it "encodes integers" do
      Base62.encode(91574294826053).should eq "Q0DRQksv"
    end
  end

  describe ".decode" do
    it "decodes hello world" do
      String.new(Base62.decode("73XpUgyMwkGr29M")).should eq "Hello World"
    end

    it "decodes unicode strings" do
      String.new(Base62.decode("1wJfrzvdbuFbL65vcS")).should eq "Hello, 世界"
    end

    it "restores leading zero bytes" do
      Base62.decode("0").should eq "00".hexbytes
      Base62.decode("00004gfFC3").should eq "00000000ffffffff".hexbytes
      Base62.decode("LygHZwPV2MC").should eq "ffffffff00000000".hexbytes
    end
  end

  describe ".decode_int" do
    it "decodes integers" do
      Base62.decode_int("Q0DRQksv").should eq 91574294826053
    end

    it "ignores zero padding" do
      Base62.decode_int("000Q0DRQksv").should eq 91574294826053
    end
  end
end
