#!/usr/bin/ruby

# igp.rb is an interactive gnuplot program designed for easy
#   2D plotting of time series data from CSV files.
# Copyright (C) 2013 Andrew Etringer
#
# This program (igp.rb) is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see [http://www.gnu.org/licenses/].
# 
# andrew.etringer@gmail.com

require 'open3'
require 'io/wait'
require 'optparse'

cmd = {}
opts = OptionParser.new
opts.banner = "Usage: #{File.basename( __FILE__ )} [options] [CSV File A] [CVS File B (optional)] ...
      This interactive gnuplot program will plot data from CSV file(s)."
opts.on( '-h', '--help', 'Show this message' ){ puts opts; exit }

args = opts.parse( ARGV )
if args.size < 1
  puts opts
  exit
end
infiles = args
ARGV.clear  # needed so that Kernel#gets does not begin reading from the infiles

GP_PATH = '/usr/bin/gnuplot'  # FIXME: will not work on Windows machines, Mac?
# FIXME this could be determined by reading the infile
TF_INFILE  = '%Y-%m-%d %H:%M:%S' # Input File Time Format
TF_PLOT    = '%Y-%m-%d %H:%M'    # Plot Time Format
X_AXIS_COL = 1  # first column is 1 not 0
SKIP_CSV_HEADER = '<sed -n "s/^[0-9]/&/p" '

class Time
  def days_in_month
    atimenextmonth = Time.utc( self.year, self.month, 31 ) + 86400
    ( Time.utc( atimenextmonth.year, atimenextmonth.month ) - 1 ).mday
  end
  def nextmonth
    Time.utc( self.year, self.month, self.days_in_month ) + 86400
  end
  def nextnmonths( n = 1 )
    new_time = self.nextmonth
    ( n - 1 ).to_i.times.each{ |i| new_time = new_time.nextmonth }
    return new_time
  end
  def lastmonth
    end_of_last_month = Time.utc( self.year, self.month ) - 1 # last second of last month
    Time.utc( end_of_last_month.year, end_of_last_month.month )
  end
  def lastnmonths( n = 1 )
    new_time = self.lastmonth
    ( n - 1 ).to_i.times.each{ |i| new_time = new_time.lastmonth }
    return new_time
  end
end
class String
  def to_utc
    utc_time = self.match( /(\d{4})\D*(\d{1,2})?\D*(\d{1,2})?\D*(\d{1,2})?\D*(\d{1,2})?\D*(\d{1,2})?/ )
    year, mon, day, hour, min, sec = utc_time[ 1..-1 ]
    Time.utc( year, mon, day, hour, min, sec )
  end
end

class IgpTimeSeries # < IgpSession
  ALPHA = ( 'a'..'s' ).to_a

  attr_reader :files, :vars, :stimes, :etimes, :poh
  attr_reader :stime_all, :etime_all, :stime_overlap, :etime_overlap
  attr_reader :do_title, :do_formatx
  attr_writer :poh

  def initialize( *input_files )
    @files, @vars, @stimes, @etimes = {}, {}, {}, {}
    input_files.flatten! 
    input_files.each_with_index do |file,ifile| 
      k = ALPHA[ ifile ]
      @stimes[ k ] = `/usr/bin/head -n100 #{file} | /bin/egrep ^[0-9] | /usr/bin/head -n1`.split( ',' )[ 0 ].to_utc
      @etimes[ k ] = `/usr/bin/tail -n100 #{file} | /bin/egrep ^[0-9] | /usr/bin/tail -n1`.split( ',' )[ 0 ].to_utc
      @vars[ k ] = `/usr/bin/head -n100 #{file} | /bin/egrep -i fields`.chomp.strip.split( ',')[ 1..-1 ]
      @files[ k ] = file
    end
    @stime_all = @stimes.values.sort[ 0 ]
    @etime_all = @etimes.values.sort[ -1 ]
    @stime_overlap = @stimes.values.sort[ -1 ]
    @etime_overlap = @etimes.values.sort[ 0 ]
    @stime_overlap = @etime_overlap = nil if @stime_overlap >= @etime_overlap
    @do_title = true
    @do_formatx = true
    # set initial plot default values; poh = plot_options_hash
    @poh = {
      :show_cmd  => false,
      :x_axis1   => ( @stime_overlap or @stime_all ),
      :x_axis2   => ( @etime_overlap or @etime_all ),
      :y_axis1   => nil,
      :y_axis2   => nil,
      :vars      => 'a2',
      :style     => 'lines', #'linespoints', #, 'lines',
      :linewidth => 1, 
      :misval    => nil,
      :title     => :auto,
      :format_x  => :auto, 
    }
    # keep initial @poh as @default
    @defaults = @poh.dup
#    # set @poh_prev to initial @poh to begin
#    @poh_prev = @poh.dup
  end
  
  def to_s
    display_file_info = [ "\n" ]
    @files.each do |k,v|
      display_file_info << sprintf( "%s = %s\n", k, v )
      @vars[ k ].each_with_index do |kk,ikk|
        coln = X_AXIS_COL + 1 + ikk
        display_file_info << sprintf( "  %s%-2i = %s\n", k, coln, kk )
      end
      display_file_info << "\n"
    end
    @files.each_key do |k|
      display_file_info << sprintf( "t%s = %s -> %s\n", k, @stimes[ k ].strftime( TF_PLOT ), @etimes[ k ].strftime( TF_PLOT ) )
    end
    display_file_info << "\n"
    display_file_info << sprintf( "t  = %s -> %s\n", @stime_all.strftime( TF_PLOT ), @etime_all.strftime( TF_PLOT ) )
    if @stime_overlap
      display_file_info << sprintf( "tv = %s -> %s\n", @stime_overlap.strftime( TF_PLOT ), @etime_overlap.strftime( TF_PLOT ) )
    else
      display_file_info << sprintf( "tv = nil\n" )
    end
    display_file_info << "\n"
    display_file_info
  end # def to_s

  def time_span_seconds( length, unit )
    # years and months can be variable length, but not weeks, days, or hours
    stime = @poh[ :x_axis1 ]
    syear = stime.year
    smonth = stime.month
    sday = stime.day
    shour = stime.hour
    smin= stime.min
    ssec= stime.sec
    sec = case unit
      when 'y' then ( Time.utc( syear + 1, smonth, sday, shour, smin, ssec ) ) - ( stime )
      when 'm' then ( stime.nextmonth + ( sday - 1 ) * 24 * 3600 + shour * 3600 + smin * 60 + ssec ) - ( stime )
      when 'w' then 7 * 24 * 3600
      when 'd' then 24 * 3600
      when 'h' then 3600
    end
    sec.to_f * length.to_f
  end # def time_span_seconds

  def change_options( new_opt )
    prev_state = @poh.dup.merge( :x_span => ( @poh[ :x_axis2 ] - @poh[ :x_axis1 ] ) )
    new_opt.each do |item,val|
      case item
        when :vars 
          case val
            when /\Av[np]/
              these_files = ( @poh[ :vars ] =~ /[a-s]/ ) ? @poh[ :vars ].scan( /[a-s]/ ).sort.uniq : @files.keys
              var_num = @poh[ :vars ].match( /\d+/ )[ 0 ].to_i
              var_incrementor = val.match( /\Av(.{1})/ )[ 1 ]
              case var_incrementor
                when 'n' 
                  var_num += 1
                  max_var_num = []
                  @vars.each{ |k,v| max_var_num << v.size if these_files.index( k ) }
                  var_num = [ var_num, max_var_num.max + X_AXIS_COL ].min
                when 'p' 
                  var_num -= 1
                  var_num = [ var_num, X_AXIS_COL + 1 ].max
              end
              these_files.map!{ |k| k + var_num.to_s }
              @poh[ item ] = these_files.join( ',' )
            else @poh[ item ] = val
          end
        when :time 
#    puts val.inspect
#    puts '--time--'
          # FIXME this part needs some work
          # only allow 1 of t_anchor and t_span in val (preference to last of each)
          # allow multiple t_expands
          # order them appropriately 
          # if both start and end anchors exist, then use them and ignore t_span
          # if t_exact exists, then use only that in place of t_anchor and t_span
          t_anchor_s, t_anchor_e, t_anchor_c, t_span, t_exact = nil
          t_expand = []
          val.each do |vv|
#    puts vv.inspect
            case vv
              when /\A[s]/ then t_anchor_s = vv
              when /\A[e]/ then t_anchor_e = vv
              when /\A[c]/ then t_anchor_c = vv
              when /\A[0-9.]/ then t_span = vv
              when /[<>|]/ then t_expand << vv
              when /\At/ then t_exact = vv
            end
          end
#    puts [ t_anchor_s, t_anchor_e, t_span, t_expand, t_exact ].inspect
          if [ t_anchor_s, t_anchor_e, t_anchor_c ].compact.size > 1
            t_val = [ t_anchor_s, t_anchor_e, t_anchor_c, t_expand ].flatten.compact  
          else
            # FIXME
            t_span += 'e' if ( t_anchor_e and t_span )
          end
          t_val = [ t_anchor_s, t_anchor_e, t_anchor_c, t_span, t_expand ].flatten.compact
          t_val = [ t_exact, t_expand ].flatten.compact if t_exact
#    puts t_val.inspect
          t_val.each do |tval|
#    puts tval.inspect
            t1 = @poh[ :x_axis1 ].dup
            t2 = @poh[ :x_axis2 ].dup
            t_span = t2 - t1
            case tval
              when /\As/ then @poh[ :x_axis1 ] = tval[ 1..-1 ].to_utc
              when /\Ae/ then @poh[ :x_axis2 ] = tval[ 1..-1 ].to_utc
              when /\Ac/
              #puts tval[ 1..-1 ].to_utc, ( t_span * 0.5 )
                @poh[ :x_axis1 ] = tval[ 1..-1 ].to_utc - ( t_span * 0.5 )
                @poh[ :x_axis2 ] = tval[ 1..-1 ].to_utc + ( t_span * 0.5 ) 
              when 't'
                @poh[ :x_axis1 ] = @stime_all
                @poh[ :x_axis2 ] = @etime_all
              when 'tv' 
                @poh[ :x_axis1 ] = @stime_overlap if @stime_overlap
                @poh[ :x_axis2 ] = @etime_overlap if @etime_overlap
              when /\At[a-s]/
                if @stimes[ tval[ 1 ] ]
                  @poh[ :x_axis1 ] = @stimes[ tval[ 1 ] ]
                  @poh[ :x_axis2 ] = @etimes[ tval[ 1 ] ]
                else
                  puts "no file #{tval[ 1 ]}"
                end
              else
#                t1 = @poh[ :x_axis1 ].dup
#                t2 = @poh[ :x_axis2 ].dup
#                t_span = t2 - t1
                dir = tval.match( /([<>]+)/ ).nil? ? '' : tval.match( /([<>]+)/ )[ 1 ]
                length = tval.scan( /[-0-9.]+/ )[ 0 ] || ''
                unit = tval.scan( /[ymwdh]/ )[ 0 ] || ''
                keep_stime = ( '|' == tval[ 0 ] ) ? true : nil
                keep_etime = ( '|' == tval[ -1 ] ) ? true : nil
                break if keep_stime && keep_etime
#puts [ keep_stime, dir, length, unit, keep_etime ].inspect
                change_length = length.dup
                length = length.empty? ? 1 : length.to_f
                if />>/ =~ dir
                  length *= dir.scan( '>' ).size
                  dir = '>'
                elsif /<</ =~ dir
                  length *= dir.scan( '<' ).size
                  dir = '<'
                end
                if tval =~ />/ && tval =~ /</
                  dir = ( tval.index( '>' ) < tval.index( '<' ) ) ? '><' : '<>' 
                end
#puts [ keep_stime, dir, length, unit, keep_etime ].inspect
                case dir
                  when ''
                    tss = time_span_seconds( length, unit )
                    if keep_stime
                      @poh[ :x_axis2 ] = t1 + tss
                    elsif keep_etime
                      @poh[ :x_axis1 ] = t2 - tss
                    else
                      @poh[ :x_axis1 ] = ( t1 + t_span / 2.0 ) - ( tss * 0.5 )
                      @poh[ :x_axis2 ] = ( t1 + t_span / 2.0 ) + ( tss * 0.5 )
                    end
                  when '>'
                    if keep_stime.nil? && keep_etime.nil?
                      case unit
                        when 'm' 
                          @poh[ :x_axis1 ] = t1.nextnmonths( length )
                          @poh[ :x_axis2 ] = @poh[ :x_axis1 ].nextnmonths( length )
                        when 'y'
                          @poh[ :x_axis1 ] = Time.utc( t1.year + length )
                          @poh[ :x_axis2 ] = Time.utc( @poh[ :x_axis1 ].year + length )
                        when ''
                          @poh[ :x_axis1 ] = t2 + ( t_span * ( length - 1 ) )
                          @poh[ :x_axis2 ] = t2 + ( t_span * ( length ) )
                        when /[wdh]/
                          @poh[ :x_axis1 ] = t1 + time_span_seconds( length, unit )
                          @poh[ :x_axis2 ] = @poh[ :x_axis1 ] + time_span_seconds( length, unit )
                      end
                    elsif keep_stime.nil?
                      if unit.empty?
                        @poh[ :x_axis1 ] += t_span * length
                      else
                        @poh[ :x_axis1 ] += time_span_seconds( length, unit)
                      end
                    elsif keep_etime.nil?
                      if unit.empty?
                        @poh[ :x_axis2 ] += t_span * length
                      else
                        @poh[ :x_axis2 ] += time_span_seconds( length, unit)
                      end
                    end # if
                  when '<'
                    if keep_stime.nil? && keep_etime.nil?
                      case unit
                        when 'm' 
                          @poh[ :x_axis1 ] = t1.lastnmonths( length )
                          @poh[ :x_axis2 ] = @poh[ :x_axis1 ].nextnmonths( length )
                        when 'y'
                          @poh[ :x_axis1 ] = Time.utc( t1.year - length )
                          @poh[ :x_axis2 ] = Time.utc( @poh[ :x_axis1 ].year + length )
                        when ''
                          @poh[ :x_axis1 ] = t1 - ( t_span * ( length ) )
                          @poh[ :x_axis2 ] = t1 - ( t_span * ( length - 1 ) )
                        when /[wdh]/
                          @poh[ :x_axis1 ] = t1 - time_span_seconds( length, unit )
                          @poh[ :x_axis2 ] = @poh[ :x_axis1 ] + time_span_seconds( length, unit )
                      end
                    elsif keep_stime.nil?
                      if unit.empty?
                        @poh[ :x_axis1 ] -= t_span * length
                      else
                        @poh[ :x_axis1 ] -= time_span_seconds( length, unit)
                      end
                    elsif keep_etime.nil?
                      if unit.empty?
                        @poh[ :x_axis2 ] -= t_span * length
                      else
                        @poh[ :x_axis2 ] -= time_span_seconds( length, unit)
                      end
                    end # if
                  when '<>', '><'
                    change_ratio = case change_length.to_f
                      # default behavior
                      when 0.0 then ( '<>' == dir ) ? ( 1.0 / 3 ) : 0.2
                      else change_length.to_f * 0.5
                    end
                    change_ratio = 0 if ( '0' == change_length )
                    change_ratio *= -1 if ( '><' == dir ) 
                    if change_ratio <= -0.5 && unit.empty?
                      puts "cannot shrink time axis by 100% or more: #{tval}"
                      break
                    end
                    case unit
                      when ''
                        @poh[ :x_axis1 ] -= ( change_ratio * t_span )
                        @poh[ :x_axis2 ] += ( change_ratio * t_span )
                      else
                        tss = time_span_seconds( change_ratio.abs, unit )
                        @poh[ :x_axis1 ] -= tss * ( change_ratio < 0 ? -1 : 1 )
                        @poh[ :x_axis2 ] += tss * ( change_ratio < 0 ? -1 : 1 )
                    end
                end # case dir
            end # case val
          end # tval
          # do not allow :x_axis1 to equal or exceed :x_axis2; revert to prev_state
          if @poh[ :x_axis2 ] <= @poh[ :x_axis1 ]
            @poh[ :x_axis1 ] = prev_state[ :x_axis1 ] 
            @poh[ :x_axis2 ] = prev_state[ :x_axis2 ] 
          end
        when :yaxis
          y1, y2 = val.match( /\Ay([-0-9.]*)[^-0-9.]*([-0-9.]*)/ )[ 1..-1 ]  
          @poh[ :y_axis1 ] = y1 unless y1.empty?
          @poh[ :y_axis2 ] = y2 unless y2.empty?
          # reset to nil (and use dynamic y range)
          @poh[ :y_axis1 ] = nil if y1.empty? and y2.empty?
          @poh[ :y_axis2 ] = nil if y1.empty? and y2.empty?
        when :opts
          val.each do |xval|
            xval[ 1..-1 ].split( ',' ).each do |vv|
              val_change = vv.index( '=' )
              if val_change
                # options with new values
                new_val = vv[ ( val_change + 1 )..-1 ]
                item = vv[ 0..( val_change - 1 ) ]
                case item
                  when 'style', 'linestyle', 'ls' then @poh[ :style ] = new_val
                  when 'linewidth', 'lw' then @poh[ :linewidth ] = new_val
                  when 'mis', 'miss' then @poh[ :misval ] = new_val
                  when 'formatx' then @poh[ :format_x ] = new_val
                  when 'title' then @poh[ :title ] = new_val
                  else puts "change to plot options unsupported: #{item}="
                end
              else
                item = vv
                # options without values: set a boolean or change back to default value
                case item
                  # toggle 
                  when 'show', 's' then @poh[ :show_cmd ] = ( @poh[ :show_cmd ] ) ? false : true
                  # set to default value
                  when 'style', 'linestyle', 'ls'  then @poh[ :style ] = @defaults[ :style ]
                  when 'linewidth', 'lw' then @poh[ :linewidth ] = @defaults[ :linewidth ]
                  when 'mis', 'miss' then @poh[ :misval ] = @defaults[ :misval ]
                  when 'formatx' then @poh[ :format_x ] = ( :auto == @poh[ :format_x ] ) ? nil : :auto
                  when 'title' then @poh[ :title ] = ( :auto == @poh[ :title ] ) ? nil : :auto
                  else puts "change to plot options unsupported: #{item}"
                end
              end
            end # val
          end # xval
          # else for unknown entries in change_hash
        else puts "change unsupported: #{item}"    
      end
    end # item
    # set do_title and do_formatx to false if unchanged from the previous state 
    # :title
    @do_title = ( prev_state[ :title ] == @poh[ :title ] ) ? false : true 
    if ( :auto == prev_state[ :title ] ) and ( :auto == @poh[ :title ] )
      # no need for new title if :vars is unchanged
      if new_opt[ :vars ] !~ /v[np]/
        @do_title = ( prev_state[ :vars ] == @poh[ :vars ] ) ? false : true 
      end
    end
    # :format_x
    @do_formatx = ( prev_state[ :format_x ] == @poh[ :format_x ] ) ? false : true 
    if ( :auto == prev_state[ :format_x ] ) and ( :auto == @poh[ :format_x ] )
      # no need to recompute format of x axis if x_span is unchanged
      @do_formatx = true unless ( prev_state[ :x_span ] == ( @poh[ :x_axis2 ] - @poh[ :x_axis1 ] ) )
    end
    puts @poh.inspect # to display the @poh hash each time it is changed 
  end # def change_options

  def plot_data
    # set up variables
    vfile, vcol = '', ''
    file_var_array = []

    # define anything that will precede the plot command (pre_gp_cmd)
    pre_gp_cmd = []

    # determine the plot title
    if @do_title
      case @poh[ :title ]
        # no title
        when nil
          pre_gp_cmd << 'set title'
        # determine title from :vars
        when :auto  
          more_than_one_file = false
          poh_title, suffix1, all_files = '', nil, false
          @poh[ :vars ].split( ',' ).each do |pv|
            all_files = true if pv =~ /\A\d+\Z/
          end
          @files.each do |letter,filename|
            if @poh[ :vars ] =~ /#{letter}/ or all_files
              if poh_title.empty?
                suffix1 = " (#{letter.upcase})"
                poh_title = filename.dup 
              else
                poh_title << suffix1 unless ')' == poh_title[ -1 ]
                poh_title << ", #{@files[ letter ]} (#{letter.upcase})"
                more_than_one_file = true
              end # title is nil?
            end # var plotted is from this file?
          end # letter
          if poh_title.empty?
            puts 'no file exists'; return "\n"
          end
          pre_gp_cmd << 'set title "' + poh_title + '"'
        else
          # user-defined title
          pre_gp_cmd << 'set title ' + @poh[ :title ]
      end # case :title
    end # if do_title
    # determine x axis tic label format
    # FIXME: this is too slow ? perhaps not ?
    # FIXME: option to only perform this if necessary
    if @do_formatx
      case @poh[ :format_x ]
        # let gnuplot figure it out
        when nil 
          pre_gp_cmd << 'set format x'
        # determine format_x_time from time_span
        when :auto
          format_x_time = case ( @poh[ :x_axis2 ] - @poh[ :x_axis1 ] ).to_i
            when 0..time_span_seconds( 8, 'h' )
              '"%H:%M\n%d %b\n%Y"' # 0 - 8 hours
            when 0..time_span_seconds( 5.99, 'd' )
              '"%H:00\n%d %b\n%Y"' # 0.35 - < 6 days
            when 0..time_span_seconds( 4.516, 'm' )
              '"%d %b\n%Y"' # 6 days - < 5 months
            when 0..time_span_seconds( 6, 'y' )
              '"%b\n%Y"' # 5 months - 6 years
            when 0..time_span_seconds( 200, 'y' )
              '"%Y"' # > 6 years
                #  format_x_time = '"%H:00\n%Y-%m-%d"'
                #  format_x_time = '"%H:00\n%m-%d\n%Y"'
          end
          pre_gp_cmd << 'set format x ' + format_x_time
        else
          # user-defined format_x
          pre_gp_cmd << 'set format x ' + @poh[ :format_x ]
      end # case :format_x
    end # if do_formatx

    # set up variables to plot
    #   build poh_array for determining which vars to plot
    #   expand out instances where all data columns are to be plotted
    poh_vars = []
    @poh[ :vars ].split( ',' ).delete_if{ |dv| dv.empty? }.each do |v|
      if v.match( /\d+\Z/ ).nil? 
        ( ( X_AXIS_COL + 1 )..( @vars[ v ].size + 1 ) ).each do |vv|
          poh_vars << "#{v}#{vv}"
        end
      elsif v.match( /[a-s]/ ).nil?
        @files.each_key do |vv|  
          poh_vars << "#{vv}#{v}"
        end
      else
        poh_vars << v
      end
    end
    poh_vars.each do |v|
      vfile = v.match( /\A[a-s]/ )[ 0 ]
      vcol = v.match( /\d+\Z/ )[ 0 ]
      include_file_letter = ( more_than_one_file ) ? " (#{vfile.upcase})" : '' 
      next unless @vars.keys.index( vfile ) 
      fva = []
      fva << %Q['#{SKIP_CSV_HEADER}#{@files[ vfile ]}']
        #fva << %Q[u #{X_AXIS_COL}:#{vcol}]
        #fva << %Q[u #{X_AXIS_COL}:($#{vcol}#{miss_val}?1/0:$#{vcol})]
      # handle missing values ( '' as 1/0 ) using this method: 1:($2) instead of 1:2
      fva << ( @poh[ :misval ].nil? ? %Q[u #{X_AXIS_COL}:($#{vcol})] : %Q[u #{X_AXIS_COL}:($#{vcol}#{@poh[ :misval ]}?1/0:$#{vcol})] )
      fva << %Q[t '#{@vars[ vfile ][ vcol.to_i - X_AXIS_COL - 1 ]}#{include_file_letter}']
      fva << %Q[w #{@poh[ :style ]}]
      fva << %Q[lw #{@poh[ :linewidth ]}]
      file_var_array << fva.join( ' ' )
    end
    if file_var_array.empty?
      puts 'no file exists'; return "\n"
    end
    # set up x-axis range
    xaxis = Array.new( 2 )
    xaxis[ 0 ] = @poh[ :x_axis1 ].strftime( TF_PLOT ) if @poh[ :x_axis1 ]
    xaxis[ 1 ] = @poh[ :x_axis2 ].strftime( TF_PLOT ) if @poh[ :x_axis2 ]
    xaxis.map!{ |x| x = %Q['#{x}'] if x }
    # set up y-axis range
    yaxis = Array.new( 2 )
    yaxis[ 0 ] = @poh[ :y_axis1 ] if @poh[ :y_axis1 ]
    yaxis[ 1 ] = @poh[ :y_axis2 ] if @poh[ :y_axis2 ]
    # make gnuplot plot command
    gp_cmd = "plot [#{xaxis.join( ':' )}][#{yaxis.join( ':' )}] #{file_var_array.join( ',' )}"
    puts pre_gp_cmd.join( "\n" ) if @poh[ :show_cmd ]
    puts gp_cmd if @poh[ :show_cmd ]
    pre_gp_cmd.join( ';' ) + ';' + gp_cmd
#    # set @poh_prev to current @poh
#    @poh_prev = @poh.dup
  end # def plot_data

end # class IgpTimeSeries

# create IgpTimeSeries Class Object
igp = IgpTimeSeries.new( infiles )
puts igp.to_s
#puts igp.poh

prev_user_input = 'i'

# open gnuplot 
si, so, se = Open3.popen3( GP_PATH )

# determine this version of gnuplot
gp_version = `#{GP_PATH} --version`.scan( /[\d.-]+/ )[ 0 ]
puts "using gnuplot version: #{gp_version}"

# load these initial gnuplot comands if gp_version is >= 4.2
initial_commands2 = []
if gp_version.to_f >= 4.2
  initial_commands2 = [
    %q[set style line 80 lt rgb "#808080"],
    %q[set style line 81 lt 0],
    %q[set style line 81 lt rgb "#808080"],
    %q[set border 15 back linestyle 80],
    %q[set grid front linestyle 81],
#    %q[set style line 1 lt rgb "red" lw 1 pt 1],
#    %q[set style line 2 lt rgb "blue" lw 1 pt 1],
#    %q[set style line 3 lt rgb "green" lw 1 pt 1],
#    %q[],
  ]
end

# define initial gnuplot commands
initial_commands = [ 
  %q[set xdata time],
  %Q[set timefmt '#{TF_INFILE}'],
  %q[set datafile separator ","],
  %q[set grid front],
#  %q[show timefmt],
#  %q[show term], 
]
initial_commands += initial_commands2

# execute initial gnuplot commands
initial_commands.each do |cmd|
  puts se.readline while se.ready?
  puts cmd
  si.puts cmd
  si.puts
  si.puts
  puts se.readline while se.ready?
end

# make initial plot
puts igp.poh.inspect
si.puts igp.plot_data
# set up user interface loop; loop ends when user types 'q'
# get input from user (a), parse it, create and execute a gnuplot command, or change poh and await next command
a = ''
while a do 
  si.puts
  si.puts
  puts se.readline while se.ready? 
  # get command from user (this uses Kernel#gets); remove the carriage return
  a = gets.chomp
  case a 
    when 'q','exit','quit' then break # quit this script
    when '' then a = prev_user_input # when user types carriage return only, then use previous user input again
  end
  change_hash = {}
  b = a.split # split by spaces
  c = b.shift # get first element
  while c do
    case c
      # ? == {0,1}, * == {0,}, + == {1,}
      when 'i' then puts igp.to_s; break
      when /\Ay[,\-0-9.]?/ then change_hash[ :yaxis ] = c
      when /\A-/ 
        change_hash[ :opts ] ||= []
        change_hash[ :opts ] << c
      when /\A[a-s]?\d{0,3}(,|\Z)/, /\Av[np]/ 
        # only allow the last command in change_hash
        change_hash[ :vars ] = c
      when /\At[a-sv]?\Z/, /[<>|]/, 
           /\A[sec]\d{4}\D*/, /\A[0-9.]+[ymwdh]?/
        # allow multiple changes to :time
        change_hash[ :time ] ||= []
        change_hash[ :time ] << c
      else
        # FIXME ?
        if change_hash.empty? then
          puts "attempting to run command in gnuplot..."
          si.puts a; prev_user_input = a; break # c = nil
        end
    end # case c
    c = b.shift
  end # while c
  # change plot options 
  igp.change_options( change_hash ) # unless change_hash.empty?
  # execute this command in gnuplot
  si.puts igp.plot_data unless change_hash.empty?
  prev_user_input = a
end # while a

si.close
exit
