# frozen_string_literal: false

class TestIOBuffer < Test::Unit::TestCase
  experimental = Warning[:experimental]
  begin
    Warning[:experimental] = false
    IO::Buffer.new(0)
  ensure
    Warning[:experimental] = experimental
  end

  def assert_negative(value)
    assert(value < 0, "Expected #{value} to be negative!")
  end

  def assert_positive(value)
    assert(value > 0, "Expected #{value} to be positive!")
  end

  def test_flags
    assert_equal 0, IO::Buffer::EXTERNAL
    assert_equal 1, IO::Buffer::INTERNAL
    assert_equal 2, IO::Buffer::MAPPED

    assert_equal 16, IO::Buffer::LOCKED
    assert_equal 32, IO::Buffer::PRIVATE

    assert_equal 64, IO::Buffer::IMMUTABLE
  end

  def test_endian
    assert_equal 4, IO::Buffer::LITTLE_ENDIAN
    assert_equal 8, IO::Buffer::BIG_ENDIAN
    assert_equal 8, IO::Buffer::NETWORK_ENDIAN

    assert_include [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN], IO::Buffer::HOST_ENDIAN
  end

  def test_new_internal
    buffer = IO::Buffer.new(1024, IO::Buffer::INTERNAL)
    assert_equal 1024, buffer.size
    refute buffer.external?
    assert buffer.internal?
    refute buffer.mapped?
  end

  def test_new_mapped
    buffer = IO::Buffer.new(1024, IO::Buffer::MAPPED)
    assert_equal 1024, buffer.size
    refute buffer.external?
    refute buffer.internal?
    assert buffer.mapped?
  end

  def test_new_immutable
    buffer = IO::Buffer.new(128, IO::Buffer::INTERNAL|IO::Buffer::IMMUTABLE)
    assert buffer.immutable?

    assert_raise RuntimeError do
      buffer.copy("", 0)
    end

    assert_raise RuntimeError do
      buffer.copy("!", 1)
    end
  end

  def test_file_mapped
    buffer = File.open(__FILE__) {|file| IO::Buffer.map(file)}
    assert_include buffer.to_str, "Hello World"
  end

  def test_string_mapped
    string = "Hello World"
    buffer = IO::Buffer.for(string)

    # Cannot modify string as it's locked by the buffer:
    assert_raise RuntimeError do
      string[0] = "h"
    end

    buffer.set(:U8, 0, "h".ord)

    # Buffer releases it's ownership of the string:
    buffer.free

    assert_equal "hello World", string
    string[0] = "H"
    assert_equal "Hello World", string
  end

  def test_non_string
    not_string = Object.new

    assert_raise TypeError do
      IO::Buffer.for(not_string)
    end
  end

  def test_resize
    buffer = IO::Buffer.new(1024, IO::Buffer::MAPPED)
    buffer.resize(2048, 0)
    assert_equal 2048, buffer.size
  end

  def test_resize_preserve
    message = "Hello World"
    buffer = IO::Buffer.new(1024, IO::Buffer::MAPPED)
    buffer.copy(message, 0)
    buffer.resize(2048, 1024)
    assert_equal message, buffer.to_str(0, message.bytesize)
  end

  def test_compare_same_size
    buffer1 = IO::Buffer.new(1)
    assert_equal buffer1, buffer1

    buffer2 = IO::Buffer.new(1)
    buffer1.set(:U8, 0, 0x10)
    buffer2.set(:U8, 0, 0x20)

    assert_negative buffer1 <=> buffer2
    assert_positive buffer2 <=> buffer1
  end

  def test_compare_different_size
    buffer1 = IO::Buffer.new(3)
    buffer2 = IO::Buffer.new(5)

    assert_negative buffer1 <=> buffer2
    assert_positive buffer2 <=> buffer1
  end

  def test_slice
    buffer = IO::Buffer.new(128)
    slice = buffer.slice(8, 32)
    slice.copy("Hello World", 0)
    assert_equal("Hello World", buffer.to_str(8, 11))
  end

  def test_slice_bounds
    buffer = IO::Buffer.new(128)

    # What is best exception class?
    assert_raise RuntimeError do
      buffer.slice(128, 10)
    end

    # assert_raise RuntimeError do
    #   pp buffer.slice(-10, 10)
    # end
  end

  def test_locked
    buffer = IO::Buffer.new(128, IO::Buffer::INTERNAL|IO::Buffer::LOCKED)

    assert_raise RuntimeError do
      buffer.resize(256, 0)
    end

    assert_equal 128, buffer.size

    assert_raise RuntimeError do
      buffer.free
    end

    assert_equal 128, buffer.size
  end

  def test_invalidation
    input, output = IO.pipe

    # (1) rb_write_internal creates IO::Buffer object,
    buffer = IO::Buffer.new(128)

    # (2) it is passed to (malicious) scheduler
    # (3) scheduler starts a thread which call system call with the buffer object
    thread = Thread.new{buffer.locked{input.read}}

    Thread.pass until thread.stop?

    # (4) scheduler returns
    # (5) rb_write_internal invalidate the buffer object
    assert_raise RuntimeError do
      buffer.free
    end

    # (6) the system call access the memory area after invalidation
    output.write("Hello World")
    output.close
    thread.join

    input.close
  end
end
