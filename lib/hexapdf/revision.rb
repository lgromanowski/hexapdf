# -*- encoding: utf-8 -*-

require 'hexapdf/error'
require 'hexapdf/pdf/utils/object_hash'

module HexaPDF

  # Embodies one revision of a PDF file, either the initial version or an incremental update.
  #
  # The purpose of a Revision object is to manage the objects and the trailer of one revision.
  # These objects can either be added manually or loaded from a cross-reference section or stream.
  # Since a PDF file can be incrementally updated, it can have multiple revisions.
  #
  # If a revision doesn't have an associated cross-reference section, it wasn't created from a PDF
  # file.
  #
  # See: PDF1.7 s7.5.6, Revisions
  class Revision

    include Enumerable

    # The trailer dictionary
    attr_reader :trailer

    # The callable object responsible for loading objects.
    attr_accessor :loader

    # :call-seq:
    #   Revision.new(trailer)                                           -> revision
    #   Revision.new(trailer, xref_section: section, loader: loader)    -> revision
    #   Revision.new(trailer, xref_section: section) {|entry| block }   -> revision
    #
    # Creates a new Revision object.
    #
    # Options:
    #
    # xref_section::
    #   An XRefSection object that contains information on how to load objects. If this option is
    #   specified, then a +loader+ or a block also needs to be specified!
    #
    # loader::
    #   The loader object needs to respond to +call+ taking a cross-reference entry and returning
    #   the loaded object. If no +xref_section+ is supplied, this value is not used.
    #
    #   If a block is given, it is used instead of the loader object.
    def initialize(trailer, xref_section: nil, loader: nil, &block)
      @trailer = trailer
      @loader = xref_section && (block || loader)
      @xref_section = xref_section || XRefSection.new
      @objects = HexaPDF::PDF::Utils::ObjectHash.new
    end

    # Returns the next free object number for adding an object to this revision.
    def next_free_oid
      ((a = @xref_section.max_oid) < (b = @objects.max_oid) ? b : a) + 1
    end

    # :call-seq:
    #   revision.object(ref)    -> obj or nil
    #   revision.object(oid)    -> obj or nil
    #
    # Returns the object for the given reference or object number if such an object is available
    # in this revision, or +nil+ otherwise.
    #
    # If the revision has an entry but one that is pointing to a free entry in the cross-reference
    # section, an object representing PDF null is returned.
    def object(ref)
      if ref.respond_to?(:oid)
        oid = ref.oid
        gen = ref.gen
      else
        oid = ref
      end

      if @objects.entry?(oid, gen)
        @objects[oid, gen]
      elsif (xref_entry = @xref_section[oid, gen])
        load_object(xref_entry)
      else
        nil
      end
    end

    # :call-seq:
    #   revision.object?(ref)    -> true or false
    #   revision.object?(oid)    -> true or false
    #
    # Returns +true+ if the revision contains an object
    #
    # * for the exact reference if the argument responds to :oid, or else
    # * for the given object number.
    def object?(ref)
      if ref.respond_to?(:oid)
        @objects.entry?(ref.oid, ref.gen) || @xref_section.entry?(ref.oid, ref.gen)
      else
        @objects.entry?(ref) || @xref_section.entry?(ref)
      end
    end

    # :call-seq:
    #   revision.add(obj)   -> obj
    #
    # Adds the given object (needs to be a HexaPDF::Object) to this revision and returns it.
    def add(obj)
      if object?(obj.oid)
        raise HexaPDF::Error, "A revision can only contain one object with a given object number"
      elsif !obj.indirect?
        raise HexaPDF::Error, "A revision can only contain indirect objects"
      end
      add_without_check(obj)
    end

    # :call-seq:
    #   revision.delete(ref, mark_as_free: true)
    #   revision.delete(oid, mark_as_free: true)
    #
    # Deletes the object specified either by reference or by object number from this revision by
    # marking it as free.
    #
    # If the +mark_as_free+ option is set to +false+, the object is really deleted.
    def delete(ref_or_oid, mark_as_free: true)
      return unless object?(ref_or_oid)
      ref_or_oid = ref_or_oid.oid if ref_or_oid.respond_to?(:oid)

      obj = object(ref_or_oid)
      obj.data.value = nil
      if mark_as_free
        add_without_check(HexaPDF::Object.new(nil, oid: obj.oid, gen: obj.gen))
      else
        @xref_section.delete(ref_or_oid)
        @objects.delete(ref_or_oid)
      end
    end

    # :call-seq:
    #   revision.each {|obj| block }   -> revision
    #   revision.each                  -> Enumerator
    #
    # Calls the given block once for every object of the revision.
    #
    # Objects that are loadable via an associated cross-reference section but are currently not,
    # are loaded automatically.
    def each
      return to_enum(__method__) unless block_given?

      if defined?(@all_objects_loaded)
        @objects.each {|_oid, _gen, data| yield(data)}
      else
        seen = {}
        @objects.each {|oid, _gen, data| seen[oid] = true; yield(data)}
        @xref_section.each do |oid, _gen, data|
          next if seen.key?(oid)
          yield(@objects[oid] || load_object(data))
        end
        @all_objects_loaded = true
      end

      self
    end

    private

    # Loads a single object from the associated cross-reference section.
    def load_object(xref_entry)
      add_without_check(@loader.call(xref_entry))
    end

    # Adds the object to the available objects of this revision and returns it.
    def add_without_check(obj)
      @objects[obj.oid, obj.gen] = obj
    end

  end

end