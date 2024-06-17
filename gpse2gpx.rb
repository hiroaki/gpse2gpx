#!/usr/bin/env ruby
#
# gps2gpx.rb - GPSe 形式を GPX 形式へ変換する
#
#
# 使い方：
#
#   $ ruby gpse2gpx.rb input.GPSe > output.gpx
#
#
# 変換元の GPSe 形式の Track データについて、データ仕様詳細は不明ながら、実際のデータを観察すると次のようなルールがあります：
# - 文字エンコーディング Shift_JIS で改行文字が CR
# - 地点データの集まりは 6行目から
# - 地点データはカンマ区切りで：
#     数字, 緯度, 軽度, 標高, ext0, 時刻, 定数文字列（"Track"）, コメント, ext1, ext2
#   先頭の数字は連続するいくつかの行が同じ値をもち、後ろに行くほど数字が大きくなる（ trkseg の意味に見える）
#   緯度経度は DMS 形式で、かつ 日本測地系
#   時刻のタイムゾーンは明記されておらず、おそらく JST
#
# なお 日本測地系 から 世界測地系 への変換は別のプログラム gpx-tokyo2jgd.rb を使って変換できます。
#
#
# 制限事項：
# - このプログラムでは、入力である GPSe データについては、トラックのデータしかないものと見做しています。
#   もし、ウェイポイントやルートのデータがあっても対応できていません。
# - GPSe の地点データにはトラックセグメントのような値がありますが、このプログラムではそれを無視し、
#   全体をひとつのトラック、ひとつのトラックセグメントにまとめています。
#   つまり出力される GPX データにはひとつのトラックセグメントを持った、一つのトラックのデータだけになります。
#
require './geo_tool'
require 'gpx'
require 'optparse'

module Gpse
  class Wpt
    include GeoTool

    def self.parse_line(line)
      items = line.split(/,/)

      number_of_trkseg = items[0]
      lat  = items[1]
      lon  = items[2]
      ele  = items[3]
      ext0 = items[4]
      dt   = items[5]
      type = items[6]
      comm = items[7]
      ext1 = items[8]
      ext2 = items[9]

      new(lat, lon, ele, dt)
    end

    def initialize(lat_degree, lon_degree, ele, dt)
      @lat = lat_degree.to_s
      @lon = lon_degree.to_s
      @ele = ele.to_s
      @dt = dt.to_s
    end

    def lat
      @lat
    end

    def lon
      @lon
    end

    def lat_as_dms
      deg2dms(@lat)
    end

    def lon_as_dms
      deg2dms(@lon)
    end

    def time
      Time.parse(@dt)
    end

    def ele
      @ele
    end
  end

  class Trkpt < Wpt
  end
end

class App
  def self.run
    new.perform
  end

  attr_reader :gpse_file

  def initialize
    parse_commandline!
  end

  def parse_commandline!
    @gpse_file = ARGV[0]
  end

  def perform
    gpx_file = GPX::GPXFile.new

    File.open(gpse_file) do |input|
      $/ = "\r"
      gpse_line1 = input.gets # 'GPSe'
      gpse_line2 = input.gets # 'Track'
      gpse_line3 = input.gets # 1
      gpse_line4 = input.gets # 21
      gpse_line5 = input.gets # number of trkpt(s)

      segment = GPX::Segment.new

      input.each_line do |line|
        tp = Gpse::Trkpt.parse_line(line)

        segment.points << GPX::TrackPoint.new(
          lat: tp.lat,
          lon: tp.lon,
          time: tp.time,
          elevation: tp.ele,
        )
      end

      track = GPX::Track.new(name: 'My Track')
      track.segments << segment
      gpx_file.tracks << track
    end

    puts gpx_file.to_s
  end
end

App.run
