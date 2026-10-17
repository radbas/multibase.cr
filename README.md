# Multibase.cr

Base58 (Bitcoin), Base62, Base85 (RFC 1924) and custom alphabet (BaseN) encoding for Crystal, with support for Unicode alphabets like emojis.

- **Fast**: quasi-linear time for every alphabet, using [GMP](https://gmplib.org/).
- **Strict**: invalid characters and malformed UTF-8 raise an error with their position. Nothing is silently skipped.
- **Exact**: every byte sequence has exactly one encoding, and decoding gives back the original bytes, leading zeros included.
- **Tested**: against the Bitcoin Core and RFC 1924 test vectors, and fuzzed against a naive reference implementation with hostile input.

The input is treated as one big number and converted to the target base. This is how Base58 and Base62 work, but it is not compatible with the block-based encodings of RFC 4648.

> Do not use this for Base16, Base32, Base64 or basE91.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     multibase:
       github: radbas/multibase.cr
       version: ~> 1.0
   ```

2. Run `shards install`

GMP is already required by Crystal's `big` module. On Debian/Ubuntu, install `libgmp-dev`.

## Usage

```crystal
require "multibase"

# Base62
Multibase::Base62.encode("Hello World")     # => "73XpUgyMwkGr29M"
Multibase::Base62.decode("73XpUgyMwkGr29M") # => Bytes[72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100]
String.new(Multibase::Base62.decode("73XpUgyMwkGr29M")) # => "Hello World"

# Base58 (Bitcoin alphabet)
Multibase::Base58.encode("Hello World") # => "JxF12TrwUP45BMd"

# Base85 (RFC 1924 alphabet)
Multibase::Base85.encode("Hello World") # => "7KPt{PR^XAyM<W"
```

Strings are encoded as their UTF-8 bytes. `Bytes` work the same way.

### Untrusted input

`decode?` returns `nil` instead of raising, which is useful for validation:

```crystal
Multibase::Base58.decode?("not base58!") # => nil
```

### Integers

Any non-negative `Int`, including `BigInt`, can be encoded. `decode_int` turns the string back into a `BigInt`:

```crystal
Multibase::Base62.encode(91574294826053) # => "Q0DRQksv"
Multibase::Base62.decode_int("Q0DRQksv") # => 91574294826053
Multibase::Base62.encode(0)              # => "0"
```

`decode_int` ignores leading zero characters, so zero-padded IDs like `"000Q0DRQksv"` decode to the same number.

### Custom alphabets

Any alphabet with at least 2 unique characters can be used:

```crystal
transcoder = Multibase::Transcoder.new("0123456789")
transcoder.encode(Bytes[1, 0]) # => "256"
transcoder.decode("256")       # => Bytes[1, 0]

emoji = Multibase::Transcoder.new("🍎🍌🍒🍇🍉🍋🍍🥝")
emoji.encode("Hi") # => "🍉🍉🍌🍋🍌"
```

`Transcoder` has the same methods as the built-in encodings. Create it once and reuse it: it is immutable and safe to share between fibers and threads.

Alphabets are split into Unicode codepoints (`Char`), not graphemes. For example `"☂️"` is two codepoints (`☂` and the invisible variation selector `U+FE0F`), so it counts as two symbols.

### Leading zeros

Leading zero bytes are kept as the first character of the alphabet, the same way Bitcoin's Base58 does it:

```crystal
Multibase::Base58.encode(Bytes[0, 0, 1]) # => "112"
Multibase::Base58.decode("112")          # => Bytes[0, 0, 1]
```

### IPv6 addresses (RFC 1924)

RFC 1924 defines a fixed-width encoding for 128-bit IPv6 addresses: always 20 characters. `Base85.encode` produces shorter strings for addresses with leading zero bytes, so use the dedicated methods:

```crystal
address = "108000000000000000080800200c417a".hexbytes # 1080::8:800:200C:417A
Multibase::Base85.encode_ipv6(address)                # => "4)+k&C#VzJ4br>0wv%Yp"
Multibase::Base85.encode_ipv6(1_u128)                 # => "00000000000000000001" (::1)
Multibase::Base85.decode_ipv6("4)+k&C#VzJ4br>0wv%Yp") # => Bytes[16, 128, 0, 0, 0, 0, 0, 0, 0, 8, 8, 0, 32, 12, 65, 122]
```

`encode_ipv6` takes 16 bytes or a `UInt128`. To encode an address string, newer Crystal versions can parse it with `Socket::IPAddress.parse_v6_fields?`:

```crystal
require "socket"

fields = Socket::IPAddress.parse_v6_fields?("1080::8:800:200C:417A").not_nil!
Multibase::Base85.encode_ipv6(fields.reduce(0_u128) { |acc, field| acc << 16 | field }) # => "4)+k&C#VzJ4br>0wv%Yp"
```

### Errors

All errors raise `Multibase::Error`, a subclass of `ArgumentError`:

```crystal
Multibase::Base58.decode("0OIl")       # raises Multibase::Error: Invalid character '0' at position 0
Multibase::Base58.decode("2NEpo7TZ\n") # raises Multibase::Error: Invalid character '\n' at position 8
Multibase::Base62.encode(-1)           # raises Multibase::Error: Cannot encode negative integer -1
Multibase::Transcoder.new("aa")        # raises Multibase::Error: Alphabet contains duplicate character 'a'
```

## Compatibility

| Encoding | Alphabet | Verified against |
| --- | --- | --- |
| `Base58` | Bitcoin: `1-9A-HJ-NP-Za-km-z` | [Bitcoin Core test vectors](https://github.com/bitcoin/bitcoin/blob/master/src/test/data/base58_encode_decode.json), [IETF draft](https://datatracker.ietf.org/doc/html/draft-msporny-base58-03) |
| `Base62` | `0-9A-Za-z` (GMP order) | |
| `Base85` | [RFC 1924](https://datatracker.ietf.org/doc/html/rfc1924) | RFC 1924 example (via `encode_ipv6`) |

Base58 here is plain Base58 without the Base58Check checksum.

## Security notes

- **Strict decoding.** Every character must be in the alphabet: no whitespace, no case folding, no lookalike substitution. Malformed UTF-8 is rejected even if the alphabet contains `U+FFFD`.
- **No malleability.** Different strings never decode to the same bytes, so `encode(decode(s)) == s` for every valid `s`. The exception is `decode_int`, which ignores leading zeros. If you need a unique form, compare `encode(decode_int(s)) == s`.
- **Bounded cost.** Conversion is quasi-linear for every alphabet, so large inputs cannot cause quadratic slowdowns. Converting 1 MB still takes 100–400 ms, so limit the size of untrusted input before decoding it.
- **Size limit.** Output larger than Crystal's maximum `String` size (2 GB) raises `Multibase::Error`.
- **Not constant time.** The run time depends on the data. Do not rely on this library to hide secrets from timing side channels.

## Performance

`crystal run --release bench/bench.cr` on an x86-64 laptop:

| Input | Base58 / Base62 (encode / decode) | Base85 (encode / decode) |
| --- | --- | --- |
| 32 B | 1.1 µs / 1.2 µs | 3.1 µs / 2.4 µs |
| 1 KB | 58 µs / 49 µs | 94 µs / 68 µs |
| 1 MB | 251 ms / 107 ms | 366 ms / 168 ms |

Alphabets with up to 62 characters use GMP's native conversion. Larger alphabets, such as Base85 or emojis, use divide and conquer on top of GMP's fast multiplication.

## Development

```sh
crystal spec
crystal tool format --check
shards install && mkdir -p bin && crystal build lib/ameba/bin/ameba.cr -o bin/ameba && bin/ameba
```

The fuzz specs use a fixed seed by default. To fuzz longer or with another seed:

```sh
FUZZ_SEED=1234 FUZZ_ITERATIONS=20 crystal spec spec/fuzz_spec.cr
```

## Contributing

1. Fork it (<https://github.com/radbas/multibase.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Johannes Rabausch](https://github.com/jrabausch) - creator and maintainer
