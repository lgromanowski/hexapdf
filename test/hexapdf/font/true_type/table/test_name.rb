# -*- encoding: utf-8 -*-

require 'test_helper'
require 'stringio'
require 'hexapdf/font/true_type/table/name'

describe HexaPDF::Font::TrueType::Table::Name do
  before do
    @file = Object.new
    @file.define_singleton_method(:io) { @io ||= StringIO.new(''.b) }

    @file.io.string = [0, 3, 42].pack('n3')
    @file.io.string << [1, 0, 0, 0, 4, 0].pack('n6')
    @file.io.string << [0, 3, 1, 0, 8, 4].pack('n6')
    @file.io.string << [0, 3, 2, 1, 14, 12].pack('n6')
    @file.io.string << 'hexa'.encode('MACROMAN').b << 'hexa'.encode('UTF-16BE').b <<
      'hexapdf'.encode('UTF-16BE').b

    @entry = HexaPDF::Font::TrueType::Table::Directory::Entry.new('name', 0, 0, @file.io.length)
  end

  describe "initialize" do
    it "reads the data in format 0 from the associated file" do
      table = HexaPDF::Font::TrueType::Table::Name.new(@file, @entry)
      assert_equal(0, table.format)
      assert_equal({}, table.language_tags)
      assert_equal('hexa', table[:copyright][0])
      assert_equal(1, table[:copyright][0].platform_id)
      assert_equal(0, table[:copyright][0].encoding_id)
      assert_equal(0, table[:copyright][0].language_id)
      assert_equal('hexa', table[:copyright][1])
      assert_equal(0, table[:copyright][1].platform_id)
      assert_equal(3, table[:copyright][1].encoding_id)
      assert_equal(1, table[:copyright][1].language_id)
      assert_equal('hexapdf', table[:font_family][0])
      assert_equal(0, table[:font_family][0].platform_id)
      assert_equal(3, table[:font_family][0].encoding_id)
      assert_equal(2, table[:font_family][0].language_id)
      assert_equal(table[:copyright][0], table[:copyright].preferred_record)
    end

    it "reads the data in format 1 from the associated file" do
      @file.io.string[0, 6] = [1, 3, 52].pack('n3')
      @file.io.string[42, 0] = [2, 4, 26, 4, 30].pack('n*')
      @file.io.string << 'ende'.encode('UTF-16BE').b
      table = HexaPDF::Font::TrueType::Table::Name.new(@file, @entry)
      assert_equal(1, table.format)
      assert_equal({0x8000 => 'en', 0x8001 => 'de'}, table.language_tags)
    end

    it "loads some default values if no entry is given" do
      table = HexaPDF::Font::TrueType::Table::Name.new(@file)
      assert_equal(0, table.format)
      assert_equal({}, table.records)
      assert_equal({}, table.language_tags)
    end
  end

  describe "add" do
    it "adds a new record for a name" do
      table = HexaPDF::Font::TrueType::Table::Name.new(@file)
      table.add(:postscript_name, "test")
      record = table[:postscript_name][0]
      assert_equal("test", record)
      assert_equal(HexaPDF::Font::TrueType::Table::Name::Record::PLATFORM_MACINTOSH, record.platform_id)
      assert_equal(0, record.encoding_id)
      assert_equal(0, record.language_id)
    end
  end

  describe "NameRecord" do
    before do
      @table = HexaPDF::Font::TrueType::Table::Name.new(@file, @entry)
    end

    describe "platform?" do
      it "returns the correct value" do
        assert(@table[:copyright][0].platform?(:macintosh))
        assert(@table[:copyright][1].platform?(:unicode))
        refute(@table[:copyright][0].platform?(:microsoft))
      end

      it "raises an error when called with an unknown identifier" do
        assert_raises(ArgumentError) { @table[:copyright][0].platform?(:testing) }
      end
    end

    describe "preferred?" do
      it "returns true for names in US English that had been converted to UTF-8" do
        assert(@table[:copyright][0].preferred?)
        refute(@table[:copyright][1].preferred?)
      end
    end
  end
end
