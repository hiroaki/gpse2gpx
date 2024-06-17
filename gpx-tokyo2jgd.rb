#!/usr/bin/env ruby
#
# gpx-tokyo2jgd.rb - GPX の測地系変換（日本測地系 --> 世界測地系)
#
#
# 使い方：
#
#   $ ruby gpx-tokyo2jgd.rb [-w] [-v] input.gpx > output.gpx
#
#
# 入力した GPX ファイルの全てのトラックポイント trkpt(s) について、
# 緯度経度が日本測地系であるとみなし、その値を世界測地系に変換した新たな GPX データを出力します。
#
# 実行に際していずれかの変換アルゴリズムを選択できます。
# デフォルトは (A) で、オプション -w を付与して実行した場合は (B) です：
#
#   (A) jpmobile (gem) に含まれているモジュール DatumConv による
#
#   (B) 世界測地系座標変換 (TKY2JGD) Web版 TKY2JGD
#       https://vldb.gsi.go.jp/sokuchi/surveycalc/tky2jgd/main.html
#
# オプション -v を付与すると、 (B) の実行時に、リクエストとレスポンスの進捗状況を STDERR に出力します。
# (B) は外部サービスへアクセスすることに注意してください。
#
#
# 制限事項：
# - 日本測地系 を 世界測地系 に変換しますが、逆の変換はできません。
# - ウェイポイント、ルートについては未対応です。
#   入力の GPX データにそれらが含まれていても無視されます（出力結果には含まれますが、入力値のままです）
# - 変換されたデータは、正確性や精度が求められる場面では利用できません。
#
require './geo_tool'
require 'gpx'
require 'http'
require 'jpmobile/datum_conv'
require 'logger'
require 'optparse'
require 'pathname'

class App
  include GeoTool

  def self.run
    new.perform
  end

  attr_reader :gpx_filename
  attr_reader :options
  attr_reader :use_tky2jgd
  attr_reader :verbose

  def initialize
    parse_commandline!
  end

  def use_tky2jgd?
    use_tky2jgd
  end

  private

  def parse_commandline!
    @prog_name = $0
    @options = {}
    @use_tky2jgd = false
    @verbose = false

    opt = OptionParser.new
    opt.on('-m VAL') {|v| @options[:tky2jgd] = v }
    opt.on('-w') { @use_tky2jgd = true }
    opt.on('-v') { @verbose = true }
    opt.parse!(ARGV)

    @gpx_filename = ARGV[0]
  end

  public

  def perform
    gpx_file = GPX::GPXFile.new(gpx_file: gpx_filename)

    gpx_file.tracks.each do |track|
      track.segments.each do |segment|
        latlon_jgd = if use_tky2jgd?
          tokyo2jgd_using_tky2jgd(segment.points)
        else
          tokyo2jgd_using_jpmobile(segment.points)
        end

        segment.points.each do |point|
          latlon = latlon_jgd.shift
          point.lat = latlon[0]
          point.lon = latlon[1]
        end
      end
    end

    puts gpx_file.to_s
  end

  # 東京測地系を世界測地系へ変換します。
  # points は GPX::Point インスタンスのリストで、その項目を元に変換した [lat, lon] のリストで返します。
  # アルゴリズムは jpmobile (gem) の DatumConv モジュールを用います。
  def tokyo2jgd_using_jpmobile(points)
    points.map do |pt|
      (DatumConv.tky2jgd(pt.lat, pt.lon, pt.elevation)).slice(0, 2).map { |n| n.to_s }
    end
  end

  # 東京測地系を世界測地系へ変換します。
  # points は GPX::Point インスタンスのリストで、その項目を元に変換した [lat, lon] のリストで返します。
  # アルゴリズムは Web版 TKY2JGD を用います（ HTTP 経由で外部サイトにアクセスします）
  def tokyo2jgd_using_tky2jgd(points)
    jgd_lines = _tky2jgd_web(
      StringIO.new(
        points.map { |pt| sprintf('%s %s', deg2dms(pt.lat), deg2dms(pt.lon)) }.join("\n")
      )
    )

    latlon = []
    jgd_lines.encode(Encoding::UTF_8, Encoding::SHIFT_JIS).split(/\n/).each do |line|
      if line !~ /#/
        latlon_dms = line.split(/\s+/)
        latlon.push([dms2deg(latlon_dms[0]), dms2deg(latlon_dms[1])])
      end
    end

    latlon
  end

  def _tky2jgd_web(io)
    url_base = 'https://vldb.gsi.go.jp/sokuchi/surveycalc/tky2jgd'
    logger = Logger.new(verbose ? $stderr : nil)

    input_filename = 'latlons.in'
    output_filename = Pathname.new(input_filename).sub_ext('.out')
    result_tky2jdg = nil

    # -- Request 1/4 --
    post_url = "#{url_base}/tky2jgd_csv.php"
    logger.info "--#1 request POST: #{post_url}"
    response1 = HTTP.post(post_url, form: {
      sokuti: 1, # "日本測地系 → 世界測地系"
      Place: 0, # "緯度・経度 → 緯度・経度"
      inputname: 'off', # "入力値を出力する"
      file: HTTP::FormData::File.new(io, filename: input_filename),
    })

    logger.info "response code: #{response1.code}"
    unless response1.status.success?
      raise "Error: #{response1.status}"
    end

    # "セッションID" らしきクッキーが得られますが、使わなくてもよさそうです。
    cookie_jar = response1.cookies

    # -- Request 2/4 --
    tm = (Time.now.to_f * 1000).to_i
    sokuti = 1      # "日本測地系 → 世界測地系"
    place = 0       # "緯度・経度 → 緯度・経度"
    zone = 0        # ?
    inputname = 0   # "入力値を出力する"

    csv = "#{url_base}/tky2jgd_csv.pl?place=#{place}&zone=#{zone}&inputname=#{inputname}&filename=#{input_filename}&sokuti=#{sokuti}&t=#{tm}"
    logger.info "--#2 request GET: #{csv}"
    response2 = HTTP.cookies(cookie_jar).get(csv)

    logger.info "response code: #{response2.code}"
    unless response2.status.redirect?
      raise "Error: #{response2.inspect}"
    end

    location_in_headers = response2.headers.get('Location').first
    logger.info "redirect to: #{location_in_headers}"

    # -- Request 3/4 --
    trans = "#{url_base}/#{location_in_headers}"
    logger.info "--#3 request GET: #{trans}"
    response3 = HTTP.cookies(cookie_jar).get(trans)

    logger.info "response code: #{response3.code}"
    unless response3.status.success?
      warn response3.status.to_s
    end

    # -- Request 4/4 --
    dl = "#{url_base}/csvdown.php?outfile=#{output_filename}"
    logger.info "--#4 request GET: #{dl}"
    response4 = HTTP.cookies(cookie_jar).get(dl)

    logger.info "response code: #{response4.code}"
    if response4.status.success?
      result_tky2jdg = response4.to_s
    else
      raise "Error: #{response4.inspect}"
    end

    # Shift_JIS
    response4.to_s
  end
end

App.run
