# -----------------------------------------------------------------------------
# 
# Well-known text parser for RGeo
# 
# -----------------------------------------------------------------------------
# Copyright 2010 Daniel Azuma
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# -----------------------------------------------------------------------------
;


require 'strscan'


module RGeo
  
  module WKRep
    
    
    # This class provides the functionality of parsing a geometry from
    # WKT (well-known text) format. You may also customize the parser
    # to recognize PostGIS EWKT extensions to the input, or Simple
    # Features Specification 1.2 extensions for Z and M coordinates.
    # 
    # To use this class, create an instance with the desired settings and
    # customizations, and call the parse method.
    # 
    # === Configuration options
    # 
    # The following options are recognized. These can be passed to the
    # constructor, or set on the object afterwards.
    # 
    # <tt>:default_factory</tt>::
    #   The default factory for parsed geometries, used when no factory
    #   generator is provided. If no default is provided either, the
    #   default cartesian factory will be used as the default.
    # <tt>:factory_generator</tt>::
    #   A factory generator that should return a factory based on the
    #   srid and dimension settings in the input. The factory generator
    #   should understand the configuration options <tt>:srid</tt>,
    #   <tt>:support_z_coordinate</tt>, and <tt>:support_m_coordinate</tt>.
    #   See RGeo::Features::FactoryGenerator for more information.
    #   If no generator is provided, the <tt>:default_factory</tt> is
    #   used.
    # <tt>:support_ewkt</tt>::
    #   Activate support for PostGIS EWKT type tags, which appends an "M"
    #   to tags to indicate the presence of M but not Z, and also
    #   recognizes the SRID prefix. Default is false.
    # <tt>:support_wkt12</tt>::
    #   Activate support for SFS 1.2 extensions to the type codes, which
    #   use a "M", "Z", or "ZM" token to signal the presence of Z and M
    #   values in the data. SFS 1.2 types such as triangle, tin, and
    #   polyhedralsurface are NOT yet supported. Default is false.
    # <tt>:strict_wkt11</tt>::
    #   If true, parsing will proceed in SFS 1.1 strict mode, which
    #   disallows any values other than X or Y. This has no effect if
    #   support_ewkt or support_wkt12 are active. Default is false.
    # <tt>:ignore_extra_tokens</tt>::
    #   If true, extra tokens at the end of the data are ignored. If
    #   false (the default), extra tokens will trigger a parse error.
    
    class WKTParser
      
      
      # Create and configure a WKT parser. See the WKTParser
      # documentation for the options that can be passed.
      
      def initialize(opts_={})
        @default_factory = opts_[:default_factory] || Cartesian.preferred_factory
        @factory_generator = opts_[:factory_generator]
        @support_ewkt = opts_[:support_ewkt] ? true : false
        @support_wkt12 = opts_[:support_wkt12] ? true : false
        @strict_wkt11 = @support_ewkt || @support_wkt12 ? false : opts_[:strict_wkt11] ? true : false
        @ignore_extra_tokens = opts_[:ignore_extra_tokens] ? true : false
      end
      
      
      # Returns the default factory. See WKTParser for details.
      def default_factory
        @default_factory
      end
      
      # Sets the default factory. See WKTParser for details.
      def default_factory=(value_)
        @default_factory = value_ || Cartesian.preferred_factory
      end
      
      # Returns the factory generator, or nil if there is none.
      # See WKTParser for details.
      def factory_generator
        @factory_generator
      end
      
      # Sets the factory_generator. See WKTParser for details.
      def factory_generator=(value_)
        @factory_generator = value_
      end
      
      # Sets the factory_generator to the given block.
      # See WKTParser for details.
      def to_generate_factory(&block_)
        @factory_generator = block_
      end
      
      # Returns true if this parser supports EWKT.
      # See WKTParser for details.
      def support_ewkt?
        @support_ewkt
      end
      
      # Sets the the support_ewkt flag. See WKTParser for details.
      def support_ewkt=(value_)
        @support_ewkt = value_ ? true : false
      end
      
      # Returns true if this parser supports SFS 1.2 extensions.
      # See WKTParser for details.
      def support_wkt12?
        @support_wkt12
      end
      
      # Sets the the support_wkt12 flag. See WKTParser for details.
      def support_wkt12=(value_)
        @support_wkt12 = value_ ? true : false
      end
      
      # Returns true if this parser strictly adheres to WKT 1.1.
      # See WKTParser for details.
      def strict_wkt11?
        @strict_wkt11
      end
      
      # Sets the the strict_wkt11 flag. See WKTParser for details.
      def strict_wkt11=(value_)
        @strict_wkt11 = value_ ? true : false
      end
      
      # Returns true if this parser ignores extra tokens.
      # See WKTParser for details.
      def ignore_extra_tokens?
        @ignore_extra_tokens
      end
      
      # Sets the the ignore_extra_tokens flag. See WKTParser for details.
      def ignore_extra_tokens=(value_)
        @ignore_extra_tokens = value_ ? true : false
      end
      
      
      # Parse the given string, and return a geometry object.
      
      def parse(str_)
        str_ = str_.downcase
        @cur_factory = @factory_generator ? nil : @default_factory
        if @cur_factory
          @cur_factory_support_z = @cur_factory.has_capability?(:z_coordinate) ? true : false
          @cur_factory_support_m = @cur_factory.has_capability?(:m_coordinate) ? true : false
        end
        @cur_expect_z = nil
        @cur_expect_m = nil
        @cur_srid = nil
        if @support_ewkt && str_ =~ /^srid=(\d+);/i
          str_ = $'
          @cur_srid = $1.to_i
        end
        begin
          _start_scanner(str_)
          obj_ = _parse_type_tag(false)
          if @cur_token && !@ignore_extra_tokens
            raise Errors::ParseError, "Extra tokens beginning with #{@cur_token.inspect}."
          end
        ensure
          _clean_scanner
        end
        obj_
      end
      
      
      def _check_factory_support  # :nodoc:
        if @cur_expect_z && !@cur_factory_support_z
          raise Errors::ParseError, "Geometry calls for Z coordinate but factory doesn't support it."
        end
        if @cur_expect_m && !@cur_factory_support_m
          raise Errors::ParseError, "Geometry calls for M coordinate but factory doesn't support it."
        end
      end
      
      
      def _ensure_factory  # :nodoc:
        unless @cur_factory
          if @factory_generator
            @cur_factory = @factory_generator.call(:srid => @cur_srid, :support_z_coordinate => @cur_expect_z, :support_m_coordinate => @cur_expect_m)
          end
          @cur_factory ||= @default_factory
          @cur_factory_support_z = @cur_factory.has_capability?(:z_coordinate) ? true : false
          @cur_factory_support_m = @cur_factory.has_capability?(:m_coordinate) ? true : false
          _check_factory_support unless @cur_expect_z.nil?
        end
        @cur_factory
      end
      
      
      def _parse_type_tag(contained_)  # :nodoc:
        _expect_token_type(::String)
        if @support_ewkt && @cur_token =~ /^(.+)(m)$/
          type_ = $1
          zm_ = $2
        else
          type_ = @cur_token
          zm_ = ''
        end
        _next_token
        if zm_.length == 0 && @support_wkt12 && @cur_token.kind_of?(::String) && @cur_token =~ /^z?m?$/
          zm_ = @cur_token
          _next_token
        end
        if zm_.length > 0 || @strict_wkt11
          creating_expectation_ = @cur_expect_z.nil?
          expect_z_ = zm_[0,1] == 'z' ? true : false
          if @cur_expect_z.nil?
            @cur_expect_z = expect_z_
          elsif expect_z_ != @cur_expect_z
            raise Errors::ParseError, "Surrounding collection has Z but contained geometry doesn't."
          end
          expect_m_ = zm_[-1,1] == 'm' ? true : false
          if @cur_expect_m.nil?
            @cur_expect_m = expect_m_
          else expect_m_ != @cur_expect_m
            raise Errors::ParseError, "Surrounding collection has M but contained geometry doesn't."
          end
          if creating_expectation_
            if @cur_factory
              _check_factory_support
            else
              _ensure_factory
            end
          end
        end
        case type_
        when 'point'
          _parse_point(true)
        when 'linestring'
          _parse_line_string
        when 'polygon'
          _parse_polygon
        when 'geometrycollection'
          _parse_geometry_collection
        when 'multipoint'
          _parse_multi_point
        when 'multilinestring'
          _parse_multi_line_string
        when 'multipolygon'
          _parse_multi_polygon
        else
          raise Errors::ParseError, "Unknown type tag: #{type_.inspect}."
        end
      end
      
      
      def _parse_coords  # :nodoc:
        _expect_token_type(::Numeric)
        x_ = @cur_token
        _next_token
        _expect_token_type(::Numeric)
        y_ = @cur_token
        _next_token
        extra_ = []
        if @cur_expect_z.nil?
          while ::Numeric === @cur_token
            extra_ << @cur_token
            _next_token
          end
          num_extras_ = extra_.size
          @cur_expect_z = num_extras_ > 0 && (!@cur_factory || @cur_factory_support_z) ? true : false
          num_extras_ -= 1 if @cur_expect_z
          @cur_expect_m = num_extras_ > 0 && (!@cur_factory || @cur_factory_support_m) ? true : false
          num_extras_ -= 1 if @cur_expect_m
          if num_extras_ > 0
            raise Errors::ParseError, "Found #{extra_.size+2} coordinates, which is too many for this factory."
          end
          _ensure_factory
        else
          val_ = 0
          if @cur_expect_z
            _expect_token_type(::Numeric)
            val_ = @cur_token
            _next_token
          end
          if @cur_factory_support_z
            extra_ << val_
          end
          val_ = 0
          if @cur_expect_m
            _expect_token_type(::Numeric)
            val_ = @cur_token
            _next_token
          end
          if @cur_factory_support_m
            extra_ << val_
          end
        end
        @cur_factory.point(x_, y_, *extra_)
      end
      
      
      def _parse_point(convert_empty_=false)  # :nodoc:
        if convert_empty_ && @cur_token == 'empty'
          point_ = _ensure_factory.multi_point([])
        else
          _expect_token_type(:begin)
          _next_token
          point_ = _parse_coords
          _expect_token_type(:end)
        end
        _next_token
        point_
      end
      
      
      def _parse_line_string  # :nodoc:
        points_ = []
        if @cur_token != 'empty'
          _expect_token_type(:begin)
          _next_token
          loop do
            points_ << _parse_coords
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
          end
        end
        _next_token
        _ensure_factory.line_string(points_)
      end
      
      
      def _parse_polygon  # :nodoc:
        inner_rings_ = []
        if @cur_token == 'empty'
          outer_ring_ = @cur_factory.linear_ring([])
        else
          _expect_token_type(:begin)
          _next_token
          outer_ring_ = _parse_line_string
          loop do
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
            inner_rings_ << _parse_line_string
          end
        end
        _next_token
        _ensure_factory.polygon(outer_ring_, inner_rings_)
      end
      
      
      def _parse_geometry_collection  # :nodoc:
        geometries_ = []
        if @cur_token != 'empty'
          _expect_token_type(:begin)
          _next_token
          loop do
            geometries_ << _parse_type_tag(true)
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
          end
        end
        _next_token
        _ensure_factory.collection(geometries_)
      end
      
      
      def _parse_multi_point  # :nodoc:
        points_ = []
        if @cur_token != 'empty'
          _expect_token_type(:begin)
          _next_token
          loop do
            points_ << _parse_point
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
          end
        end
        _next_token
        _ensure_factory.multi_point(points_)
      end
      
      
      def _parse_multi_line_string  # :nodoc:
        line_strings_ = []
        if @cur_token != 'empty'
          _expect_token_type(:begin)
          _next_token
          loop do
            line_strings_ << _parse_line_string
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
          end
        end
        _next_token
        _ensure_factory.multi_line_string(line_strings_)
      end
      
      
      def _parse_multi_polygon  # :nodoc:
        polygons_ = []
        if @cur_token != 'empty'
          _expect_token_type(:begin)
          _next_token
          loop do
            polygons_ << _parse_polygon
            break if @cur_token == :end
            _expect_token_type(:comma)
            _next_token
          end
        end
        _next_token
        _ensure_factory.multi_polygon(polygons_)
      end
      
      
      def _start_scanner(str_)  # :nodoc:
        @_scanner = ::StringScanner.new(str_)
        _next_token
      end
      
      
      def _clean_scanner  # :nodoc:
        @_scanner = nil
        @cur_token = nil
      end
      
      
      def _expect_token_type(type_)  # :nodoc:
        unless type_ === @cur_token
          raise Errors::ParseError, "#{type_.inspect} expected but #{@cur_token.inspect} found."
        end
      end
      
      
      def _next_token(expect_=nil)  # :nodoc:
        if @_scanner.scan_until(/\(|\)|\[|\]|,|[^\s\(\)\[\],]+/)
          token_ = @_scanner.matched
          case token_
          when /^[-+]?(\d+(\.\d*)?|\.\d+)(e[-+]?\d+)?$/
            @cur_token = token_.to_f
          when /^[a-z]+$/
            @cur_token = token_
          when ','
            @cur_token = :comma
          when '(','['
            @cur_token = :begin
          when ']',')'
            @cur_token = :end
          else
            raise Errors::ParseError, "Bad token: #{token_.inspect}"
          end
        else
          @cur_token = nil
        end
        @cur_token
      end
      
      
    end
    
    
  end
  
end
