# Run with `crystal run --release bench/bench.cr`
require "benchmark"
require "../src/multibase"

codecs = {
  "Base58"  => Multibase::Transcoder.new(Multibase::Base58::ALPHABET),
  "Base62"  => Multibase::Transcoder.new(Multibase::Base62::ALPHABET),
  "Base85"  => Multibase::Transcoder.new(Multibase::Base85::ALPHABET),
  "CJK 300" => Multibase::Transcoder.new((0x4E00...0x4E00 + 300).map(&.chr).join),
}

{32, 1024, 1024 * 1024}.each do |size|
  payload = Random.new(42).random_bytes(size)
  puts "\n#{size} bytes"
  Benchmark.ips(warmup: 0.5.seconds, calculation: 1.seconds) do |x|
    codecs.each do |name, codec|
      encoded = codec.encode(payload)
      x.report("#{name} encode") { codec.encode(payload) }
      x.report("#{name} decode") { codec.decode(encoded) }
    end
  end
end
