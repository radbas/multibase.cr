require "big"

# :nodoc:
# Conversions between bytes and `BigInt` using GMP directly.
module Multibase::GMP
  lib LibGMPExt
    fun gmpz_import = __gmpz_import(rop : LibGMP::MPZ*, count : LibC::SizeT, order : LibC::Int, size : LibC::SizeT, endian : LibC::Int, nails : LibC::SizeT, op : Void*)
    fun gmpz_export = __gmpz_export(rop : Void*, countp : LibC::SizeT*, order : LibC::Int, size : LibC::SizeT, endian : LibC::Int, nails : LibC::SizeT, op : LibGMP::MPZ*) : Void*
  end

  # Reads *bytes* as a big-endian unsigned number.
  def self.import(bytes : Bytes) : BigInt
    BigInt.new do |mpz|
      LibGMPExt.gmpz_import(mpz, bytes.size, 1, 1, 1, 0, bytes.to_unsafe.as(Void*))
    end
  end

  # Returns the number of bytes needed to store *value*, `0` for zero.
  def self.byte_size(value : BigInt) : Int32
    value.zero? ? 0 : ((LibGMP.sizeinbase(value, 2) + 7) // 8).to_i
  end

  # Writes *value* as a big-endian number of *size* bytes, left padded with
  # zero bytes. *size* must be at least `byte_size(value)`.
  def self.export(value : BigInt, size : Int32) : Bytes
    bytes = Bytes.new(size)
    unless value.zero?
      offset = size - byte_size(value)
      LibGMPExt.gmpz_export((bytes + offset).to_unsafe.as(Void*), nil, 1, 1, 1, 0, value)
    end
    bytes
  end
end
