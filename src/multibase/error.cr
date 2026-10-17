module Multibase
  # Raised for every error in this library: invalid input, invalid alphabets
  # and values that cannot be encoded.
  #
  # It is an `ArgumentError`, so `rescue ArgumentError` catches it as well.
  class Error < ArgumentError
  end
end
