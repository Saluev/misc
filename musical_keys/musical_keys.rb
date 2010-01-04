#!/usr/bin/env /usr/local/jruby-1.4.0/bin/jruby

require 'java'
require 'miglayout-3.7-swing.jar'
require 'set'
require 'enumerator'
$note_intervals = {
  'c' => 0,
  'c#' => 1,
  'd' => 2,
  'd#' => 3,
  'e' => 4,
  'f' => 5,
  'f#' => 6,
  'g' => 7,
  'g#' => 8,
  'a' => 9,
  'a#' => 10,
  'b' => 11
}
$note_intervals_inverted = $note_intervals.invert
$qwerty = [
  '1234567890-='.scan(/./),
  'qwertyuiop[]'.scan(/./),
  "asdfghjkl;'".scan(/./),
  'zxcvbnm,./'.scan(/./)
].reverse
$dvorak = [
  '1234567890[]'.scan(/./),
  "',.pyfgcrl/=".scan(/./),
  'aoeuidhtns-'.scan(/./),
  ';qjkxbmwvz'.scan(/./)  
].reverse
$keyboard = $dvorak
$velocity = 100
$base = 48

def note_to_pitch(sym)
  return nil if sym.nil?
  s = sym.to_s
  octave = s[-1].chr.to_i
  note = s[0..-2]
  return octave * 12 + $note_intervals[note]
end

def pitch_to_note(pitch)
  octave = pitch / 12
  note_interval = pitch % 12
  note = $note_intervals_inverted[note_interval]
  return "#{note.upcase}#{octave}".to_sym
end

class ChromaticLayout
  def to_s
    "Chromatic"
  end
  
  def call(k)
    ret = nil
    $keyboard.each_with_index do |row, r|
      row.each_with_index do |key, c|
        if key == k.chr.downcase then
          ret = ($base + r * 5 + c)
        end
      end
    end
    return ret
  end
end

class WholeToneLayout
  def to_s
    "Whole Tone"
  end
  
  def call(k)
    ret = nil
    $keyboard.each_with_index do |row, r|
      row.each_with_index do |key, c|
        if key == k.chr.downcase then
          ret = ($base + r * 5 + (c * 2))
        end
      end
    end
    return ret
  end
end

class MappingLayout # abstract
  def mapping
    raise "mapping not implemented"
  end
  
  def call(k)
    ret = nil
    $keyboard.each_with_index do |row, r|
      row.each_with_index do |key, c|
        if key == k.chr.downcase then
          ret = note_to_pitch(mapping[r][c])
        end
      end
    end
    return ret
  end
end

class ScaleLayout < MappingLayout
  def to_s
    "Scale"
  end
  
  def mapping
    [
      [:b4, :cs5, :ds5, :f5, :fs5, :fs5, :fs5, :gs5, :as5, :c6, :cs6, :ds6],
      [:c5, :d5, :e5, :f5, :g5, :f5, :g5, :a5, :b5, :c6, :d6, :e6],
      [:b3, :cs4, :ds4, :f4, :fs4, :fs4, :fs4, :gs4, :as4, :c5, :cs5],
      [:c4, :d4, :e4, :f4, :g4, :f4, :g4, :a4, :b4, :c5]
    ].reverse
  end
  
end

class PentatonicLayout < MappingLayout
  def to_s
    "Pentatonic"
  end
  
  def mapping
    [
      [:e6, :g6, :a6, :c7, :d7, :e7, :g7, :a7, :c8, :d8, :e8, :g8, :a8],
      [:g5, :a5, :c6, :d6, :e6, :g6, :a6, :c7, :d7, :e7, :g7, :a7],
      [:a4, :c5, :d5, :e5, :g5, :a5, :c6, :d6, :e6, :g6, :a6],
      [:c4, :d4, :e4, :g4, :a4, :c5, :d5, :e5, :g5, :a5]
    ].reverse
  end
end


  
class MidiChannel
  def initialize(real_channel, index)
    @channel = real_channel
    @index = index
  end
  
  def noteOn(pitch, velocity)
    @channel.noteOn(pitch, velocity)
  end
  
  def noteOff(pitch, velocity)
    @channel.noteOff(pitch, velocity)
  end
  
  def allNotesOff
    @channel.allNotesOff
  end
  
  def programChange(bank, program)
    @channel.programChange(bank, program)
  end
  
  def to_s
    "Channel #{@index}"
  end
end

class Keyboard < java.awt.Component
  
  def initialize(app)
    super()
    @app = app
  end
  
  def getPreferredSize
    java.awt.Dimension.new(600, 200)
  end
  
  def scale(num)
    
  end
  
  def paint(g)
    sx = sy = size.width.to_f / getPreferredSize.width.to_f
    g.scale(sx, sy) if sx > 0
    gap = 5
    round = 5
    width = height = 42.7
    $keyboard.reverse.each_with_index do |row_chars, row|
      row_chars.each_with_index do |char, col|
        x = gap + (row * width / 2) + col * (width + gap)
        y = gap + row * (height + gap)
        rect = java.awt.geom.RoundRectangle2D::Double.new(
          x, y, width, height, round, round)
          
        
        code = char[0]
        
        if @app.current_notes.include?(code)
          org_color = g.color
          g.color = java.awt.Color.new(188, 188, 188)
          g.fill(rect)
          g.color = org_color
        end
        g.draw(rect)
        pitch = @app.pitch_for_char(code)
        if pitch
          note = pitch_to_note(pitch)
          g.drawString(note.to_s, x + gap, y + gap + gap * 2)
        end
      end
    end
  end
  
end

class App
  include java.awt.event.WindowListener
  include java.awt.event.KeyListener
  include java.awt.event.ActionListener
  include java.awt.event.MouseWheelListener
  attr_accessor :current_notes
  def initialize
    @mappings = [
      ChromaticLayout.new, ScaleLayout.new, 
      WholeToneLayout.new, PentatonicLayout.new]
    @current_mapping = @mappings.first
    @current_notes = {}
    @offset_octaves = 0
    @last_wheel_moved = nil
    initialize_synth
    initialize_frame
  end
  
  def initialize_frame
    @frame = javax.swing.JFrame.new('Musical Keys')
    @frame.addWindowListener(self)
    
    @frame.addKeyListener(self)
    @frame.addMouseWheelListener(self)
    panel = javax.swing.JPanel.new
    panel.layout = java.awt.BorderLayout.new
      form_panel = javax.swing.JPanel.new
      form_panel.layout = Java::net.miginfocom.swing.MigLayout.new("fill")
        @channel_select = javax.swing.JComboBox.new(@channels.to_java)
        @channel_select.focusable = false
        @channel_select.addActionListener(self)
        form_panel.add(javax.swing.JLabel.new("Channel"))
        form_panel.add(@channel_select, "growx, wrap")
      
        @mapping_select = javax.swing.JComboBox.new(@mappings.to_java)
        @mapping_select.focusable = false
        @mapping_select.addActionListener(self)
        form_panel.add(javax.swing.JLabel.new("Layout"))
        form_panel.add(@mapping_select, "growx, wrap")
      
        @instrument_select = javax.swing.JComboBox.new(@loaded_instruments)
        @instrument_select.focusable = false
        @instrument_select.addActionListener(self)
        form_panel.add(javax.swing.JLabel.new("Instrument"))
        form_panel.add(@instrument_select, "growx, wrap")
      
      
        @offset_label = javax.swing.JLabel.new
        form_panel.add(javax.swing.JLabel.new("Octave"))
        form_panel.add(@offset_label, "growx, wrap")
      
      panel.add(form_panel, java.awt.BorderLayout::NORTH)
      
      @keyboard = Keyboard.new(self)
      panel.add(@keyboard, java.awt.BorderLayout::CENTER)
      
    @frame.add(panel)
    offset_octaves_changed
    current_notes_changed
    sync_channel_program
    @frame.pack()
    @frame.setLocationRelativeTo(nil)
    @frame.show()
  end
  
  def initialize_synth
    @synth = javax.sound.midi.MidiSystem.synthesizer
    @synth.open
    @soundbank = @synth.defaultSoundbank
    @synth.loadAllInstruments(@soundbank)
    @loaded_instruments = @synth.loadedInstruments
    @channels = @synth.channels.enum_for(:each_with_index).map{|c, i| MidiChannel.new(c, i)}
    @current_channel = @channels[0]
  end
  
  def mouseWheelMoved(event)
    now = Time.now
    if @last_wheel_moved.nil? or (now - @last_wheel_moved > 0.2)
      if event.unitsToScroll > 0
        octave_down
      else
        octave_up
      end
    end
    @last_wheel_moved = now
  end
  
  def windowActivated(event);end
  def windowClosed(event);end
  def windowClosing(event);end
  def windowDeiconified(event);end
  def windowIconified(event);end
  def windowOpened(event);end
  
  def windowDeactivated(event)
    @current_channel.allNotesOff()
    @current_notes = {}
  end
  
  def current_notes_changed
    @keyboard.repaint
  end
  
  def offset_octaves_changed
    @offset_label.text = @offset_octaves.to_s
    @keyboard.repaint
  end
  
  def current_mapping_changed
    @keyboard.repaint
  end
  
  def pitch_for_char(char)
    begin
      return @current_mapping.call(char) + (@offset_octaves * 12)
    rescue
      return nil
    end
  end
  
  def pitch_for_event(event)
    pitch_for_char(event.getKeyChar)
  end
  
  def sync_channel_program
    instrument = @instrument_select.selectedItem
    @current_channel.programChange(instrument.patch.bank, instrument.patch.program)
  end
  
  def actionPerformed(event)
    if event.source == @channel_select
      @current_channel = @channel_select.selectedItem
    elsif event.source == @mapping_select
      @current_mapping = @mapping_select.selectedItem
      current_mapping_changed
    elsif event.source == @instrument_select
      sync_channel_program
    end
  end
  
  def octave_up
    @offset_octaves += 1
    offset_octaves_changed
  end
  
  def octave_down
    @offset_octaves -= 1
    offset_octaves_changed
  end
  
  def keyPressed(event)
    key_code = event.getKeyCode
    if key_code == 38 # up arrow
      octave_up
    elsif key_code == 40 # down arrow
      octave_down
    else
      key_char = event.getKeyChar
      pitch = pitch_for_event(event)
      return if pitch.nil?
      if not @current_notes.include?(key_char)
        @current_notes[key_char] = pitch
        current_notes_changed
        @current_channel.noteOn(pitch, $velocity)
      end
    end
  end
  
  def keyReleased(event)
    key_char = event.getKeyChar
    pitch = @current_notes[key_char]
    return if pitch.nil?
    @current_notes.delete(key_char)
    current_notes_changed
    @current_channel.noteOff(pitch, $velocity)
  end
  
  def keyTyped(event);end
end

App.new