require 'json'

# 存取 CBETA 缺字資料庫
class CBETA::Gaiji
	# 載入 CBETA 缺字資料庫
  def initialize()
    fn = File.join(File.dirname(__FILE__), '../data/gaiji.json')
    @gaijis = JSON.parse(File.read(fn))
  end

  # 取得缺字資訊
  #
  # @param cb [String] 缺字 CB 碼
  # @return [Hash{String => Strin, Array<String>}] 缺字資訊
  # @return [nil] 如果該 CB 碼在 CBETA 缺字庫中不存在
  #
  # @example
  #   g = Cbeta::Gaiji.new
  #   g["CB01002"]
  #
  # Return:
  #   {
  #     "zzs": "[得-彳]",
  #     "unicode": "3775",
  #     "unicode-char": "㝵",
  #     "zhuyin": [ "ㄉㄜˊ", "ㄞˋ" ]
  #   }
  def [](cb)
  	@gaijis[cb]
  end

  # 傳入缺字 CB 碼，傳回注音 array
  #
  # 資料來源：CBETA 於 2015.5.15 提供的 MS Access 缺字資料庫
  #
  # @param cb [String] 缺字 CB 碼
  # @return [Array<String>]
  #
  # @example
  #   g = CBETA::Gaiji.new
  #   g.zhuyin("CB00023") # return [ "ㄍㄢˇ", "ㄍㄢ", "ㄧㄤˊ", "ㄇㄧˇ", "ㄇㄧㄝ", "ㄒㄧㄤˊ" ]
  def zhuyin(cb)
  	return nil unless @gaijis.key? cb
    @gaijis[cb]['zhuyin']
  end
  
  # 讀 XML P5 檔頭的缺字資料，更新現有缺字資料，輸出 JSON
  def update_from_p5(p5_folder, output_json_filename)
    update_from_p5_folder(p5_folder)
    s = JSON.pretty_generate(@gaijis)
    File.write(output_json_filename, s)
  end
  
  private
  def char_to_hash(char)
    r = {}
    id = char['id']
    char.xpath('charProp').each do |e|
      prop = e.at('localName').text
      case prop
      when 'composition'
        r['zzs'] = e.at('value').text
      when 'normalized form'
        r['normal'] = e.at('value').text
      else
        puts "未處理 charProp/localName: #{prop}"
      end
    end
    char.xpath('mapping').each do |e|
      case e['type']
      when 'unicode'
        u = e.text[2..-1]
        r['unicode'] = u
        r['unicode-char'] = [u.hex].pack('U')
      end
    end
    r
  end
  
  def update_from_p5_file(fn)
    f = File.open(fn)
    doc = Nokogiri::XML(f)
    f.close
    doc.remove_namespaces!()
    doc.xpath("//charDecl/char").each do |char|
      @gaijis[char['id']] = char_to_hash(char)
    end
  end
  
  def update_from_p5_folder(folder)
    Dir.entries(folder).each do |f|
      path = File.join(folder, f)
      next if f.start_with? '.'
      if Dir.exist? path
        update_from_p5_folder path
      else
        update_from_p5_file path
      end
    end
  end
end