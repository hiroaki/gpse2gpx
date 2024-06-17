module GeoTool
  def deg2dms(deg)
    degree, others = deg.to_s.split(/\./)
    min, extra = ("0.#{others}".to_f * 60).to_s.split(/\./)

    sec_source = "0.#{extra}"
    sec = (sec_source.to_f * 60).to_s
    sec = sprintf('%02d.%s', (sec_source.to_f * 60), (sprintf('%0.5f', (sec_source.to_f * 60))).split('.')[1])

    sprintf('%d%02d%s', degree, min, sec)
  end

  def dms2deg(dms)
    left, right = dms.split('.')
    sec = [left.slice(-2, 2), right].join('.')
    min = left.slice(-4, 2)
    deg = left.reverse.slice(4,10).reverse
    sprintf('%.8f', (deg.to_f) + (min.to_f / 60.0) + (sec.to_f / 60 / 60))
  end
end

