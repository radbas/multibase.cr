# Multibase.cr

Base transcoder for Base58, Base62, Base85 (RFC 1924) and custom alphabets (BaseN), with support for multibyte character alphabets.
This library treats the input as one big number and converts it to the target base, so it is not compatible with RFC 4648.

> Do not use for Base16, Base32, Base64 or basE91

Conversions use [GMP](https://gmplib.org/), which Crystal's `big` module already depends on (`libgmp-dev` on Debian/Ubuntu).

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     multibase:
       github: radbas/multibase.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "multibase"

# Base62
Multibase::Base62.encode("Hello World")     # => "73XpUgyMwkGr29M"
Multibase::Base62.decode("73XpUgyMwkGr29M") # => Bytes[72, 101, 108, ...]
String.new(Multibase::Base62.decode("73XpUgyMwkGr29M")) # => "Hello World"

# Base58 (Bitcoin alphabet)
Multibase::Base58.encode("Hello World") # => "JxF12TrwUP45BMd"

# Base85 (RFC 1924)
Multibase::Base85.encode("Hello World") # => "7KPt{PR^XAyM<W"

# Integers (any non-negative Int, including BigInt)
Multibase::Base62.encode(91574294826053) # => "Q0DRQksv"
Multibase::Base62.encode(0)              # => "0"
```

### Custom alphabets

Any alphabet with at least 2 unique characters can be used:

```crystal
transcoder = Multibase::Transcoder.new("0123456789")
transcoder.encode(Bytes[1, 0])  # => "256"
transcoder.decode("256")        # => Bytes[1, 0]

emoji = Multibase::Transcoder.new("🍎🍌🍒🍇🍉🍋🍍🥝")
emoji.encode("Hi")              # => "🍉🍉🍌🍋🍌"
```

Alphabets are split into Unicode codepoints (`Char`), not graphemes. For example `"☂️"` is made of two codepoints (`☂` and the invisible variation selector `U+FE0F`), so it counts as two symbols.

### Leading zeros

Leading zero bytes are preserved and encoded as the first character of the alphabet, the same way Bitcoin's Base58 does it:

```crystal
Multibase::Base58.encode(Bytes[0, 0, 1]) # => "112"
Multibase::Base58.decode("112")          # => Bytes[0, 0, 1]
```

### Errors

All errors are raised as `ArgumentError`:

```crystal
Multibase::Base58.decode("0OIl") # raises ArgumentError: Invalid character '0' at position 0
Multibase::Base62.encode(-1)     # raises ArgumentError: Cannot encode negative integer -1
Multibase::Transcoder.new("aa")  # raises ArgumentError: Alphabet contains duplicate character 'a'
```

## Development

```sh
crystal spec
crystal tool format --check
shards install && mkdir -p bin && crystal build lib/ameba/bin/ameba.cr -o bin/ameba && bin/ameba
```

## Contributing

1. Fork it (<https://github.com/radbas/multibase.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Johannes Rabausch](https://github.com/jrabausch) - creator and maintainer
