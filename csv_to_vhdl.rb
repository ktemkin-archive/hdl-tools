#!/usr/bin/env ruby
#
# csv_to_vhdl.rb
# 
# Quick script to convert Logic Analyzer output to a VHDL testbench.
# Should also support oscilloscope output in the future.
#

require 'csv'
require 'trollop'

#
# Read in options fro the command line.
#
options = Trollop::options do
  version "CSV to VHDL (c) 2013 Kyle J. Temkin"
  banner <<-EOS
    CSV to VHDL converts logic analyzer (or oscilloscope) output into VHDL testbench waveforms.
    This easily allows one to run simulations against captures of real sensor input.

    Usage:

      test [options] <csv_filename>

    where [options] are:
  EOS

  opt :time_column, "The name of the column in the CSV which encodes sample times.", :default => 'Time[s]'
  opt :entity, "If provided, a full VHDL template will be generated using the given entity name.", :type => :string
  opt :signal_type, "For use with --entity. Specfies the data type to be used for the captured signals.", :default => 'std_ulogic'
end

time_column = options[:time_column]


#
# Parse each of the samples in the CSV.
# 

samples = {}
times = []
last_sample_time = 0

least_sample_difference = Float::INFINITY 
least_runtime_duration = 0

CSV.foreach(ARGV.first, :headers => true) do |row|

  #Ensure that we never have an negative duration.
  #This easily fixes 
  last_sample_time = [last_sample_time, row[time_column].to_f].min

  #Determine the duration for which this sample will be presented;
  sample_difference = row[time_column].to_f - last_sample_time
  times << "#{sample_difference} sec"

  #Keep track of the current sample time, and the least difference
  #between sample times.
  last_sample_time = row[time_column].to_f
  least_sample_difference = [least_sample_difference, sample_difference].min if sample_difference > 0
  least_runtime_duration += sample_difference

  #And add each of the other samples to an appropriately named array.
  row.each do |name, value|
    value.strip!

    #If this is our time column, replace the time with a duration.
    next if name == time_column

    #And append the sample to the appropriate array.
    samples[name] ||= []
    samples[name] << "'#{value}'"

  end

end

#
# Generate the relevant code.
#

if options[:entity]

  #Start the entity and architecture.
  puts <<-EOS
----------------------------------------------------------------------------------
-- Testbench file: #{options[:entity]}
--
-- Generated automatically from Logic Analyzer / Oscilloscope output
-- by csv_to_vhdl; a tool by Kyle Temkin <ktemkin@binghamton.edu>.
--
-- Minimum recommended simulation duration: #{"%.3e" % least_runtime_duration} sec
-- Minimum recommended simulation precision: #{"%.3e" % least_sample_difference} sec
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity #{options[:entity]} is
end entity;


architecture captured_waveforms of #{options[:entity]} is

  --Signals automatically generated from CSV file:
  EOS

  #Add each of the signals... 
  samples.each { |name, _| puts "  signal #{name} : #{options[:signal_type]};" }

end

#Output standard types for simulation.
puts
puts "  --Delays between the samples captured from the instrument."
puts "  --These are used to re-create the captured waveforms."
puts "  type sample_delay_times is array(natural range <>) of time;"
puts "  constant duration_of_previous_sample : sample_delay_times := (#{times.join(",")});"
puts
puts "  --The actual samples captured by the instrument."
puts "  --These are used to re-create the captured waveforms."
puts "  type std_ulogic_samples is array(natural range <>) of std_ulogic;"

#Output an array for each of the values to include.
samples.each do |name, values|
  puts "  constant #{name}_samples : std_ulogic_samples := (#{values.join(", ")});"
end

puts "\nbegin" if options[:entity]

#Create the stimulus process.
puts
puts
puts "  --Main stimulus process. This process applies the captured waveforms."
puts "  process"
puts "  begin"
puts "    --Loop through all of the captured samples."
puts "    for i in 0 to #{times.count - 1} loop"
puts "      wait for duration_of_previous_sample(i);"
samples.each { |name, _| puts "      #{name} <= #{name}_samples(i);" }
puts "    end loop;"
puts "  end process;"

puts "\nend captured_waveforms;" if options[:entity]

