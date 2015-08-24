require 'cgi'
require 'date'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'set'
require 'gepub'
require 'pp'

# Convert CBETA XML P5a to EPUB
#
# CBETA XML P5a 可由此取得: https://github.com/cbeta-git/xml-p5a
class CBETA::P5aToEPUB
  # 內容不輸出的元素
  PASS=['back', 'teiHeader']

  # 某版用字缺的符號
  MISSING = '－'
  
  SCRIPT_FOLDER = File.dirname(__FILE__)
  NAV_TEMPLATE = File.read(File.join(SCRIPT_FOLDER, '../data/epub-nav.xhtml'))
  MAIN = 'main.xhtml'  
  DATA = File.join(SCRIPT_FOLDER, '../data')

  # @param temp_folder [String] 供 EPUB 暫存工作檔案的路徑
  # @param options [Hash]
  #   :epub_version [Integer] EPUB 版本，預設為 3
  #   :graphic_base [String] 圖檔路徑
  #   :readme [String] 說明檔，如果沒指定的話，就使用預設說明檔
  def initialize(temp_folder, options={})
    @temp_folder = temp_folder
    @settings = {
      epub_version: 3,
      readme: File.join(DATA, 'epub-readme.xhtml')
    }
    @settings.merge!(options)
    puts @settings
    @cbeta = CBETA.new
    @gaijis = CBETA::Gaiji.new
    
    # 載入 unicode 1.1 字集列表
    fn = File.join(DATA, 'unicode-1.1.json')
    json = File.read(fn)
    @unicode1 = JSON.parse(json)
  end

  # 將某個 xml 轉為一個 EPUB
  def convert_file(input_path, output_path)
    return false unless input_path.end_with? '.xml'
    
    FileUtils.remove_dir(@temp_folder, force=true)
    FileUtils::mkdir_p @temp_folder
    
    @book_id = File.basename(input_path, ".xml")
    
    sutra_init
    
    handle_file(input_path)
    create_epub(output_path)
  end

  # 將某個資料夾下的每個 xml 檔都轉為一個對應的 EPUB。
  # 資料夾可以是巢狀，全部都會遞迴處理。
  #
  # @example
  #   require 'cbeta'
  #   
  #   TEMP = '/temp/epub-work'
  #   IMG = '/Users/ray/Documents/Projects/D道安/figures'
  #   
  #   c = CBETA::P5aToEPUB.new(TEMP, IMG)
  #   c.convert_folder('/Users/ray/Documents/Projects/D道安/xml-p5a/DA', '/temp/cbeta-epub/DA')
  def convert_folder(input_folder, output_folder)
    FileUtils.remove_dir(output_folder, force=true)
    FileUtils::mkdir_p output_folder
    Dir.foreach(input_folder) do |f|
      next if f.start_with? '.'
      p1 = File.join(input_folder, f)
      if File.file?(p1)
        f.sub!(/.xml$/, '.epub')
        p2 = File.join(output_folder, f)
        convert_file(p1, p2)
      else
        p2 = File.join(output_folder, f)
        convert_folder(p1, p2)
      end
    end
  end
  
  # 將多個 xml 檔案合成一個 EPUB
  #
  # @example 大般若經 跨三冊 合成一個 EPUB
  #   require 'cbeta'
  #   
  #   TEMP = '/temp/epub-work'
  #   
  #   xml_files = [
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/05/T05n0220a.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/06/T06n0220b.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220c.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220d.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220e.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220f.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220g.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220h.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220i.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220j.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220k.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220l.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220m.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220n.xml',
  #     '/Users/ray/git-repos/cbeta-xml-p5a/T/07/T07n0220o.xml',
  #   ]
  #   
  #   c = CBETA::P5aToEPUB.new(TEMP)
  #   c.convert_sutra('T0220', '大般若經', xml_files, '/temp/cbeta-epub/T0220.epub')
  def convert_sutra(book_id, title, xml_files, out)
    @book_id = book_id
    sutra_init
    xml_files.each { |f| handle_file(f) }
    
    @title = title
    create_epub(out)
  end

  private
  
  def copy_static_files(src, dest)
    dest = File.join(@temp_folder, dest)
    FileUtils.copy(src, dest)
  end
  
  def create_epub(output_path)
    copy_static_files(@settings[:readme], 'readme.xhtml')
    
    src = File.join(DATA, 'epub-donate.xhtml')
    copy_static_files(src, 'donate.xhtml')
    
    src = File.join(DATA, 'epub.css')
    copy_static_files(src, 'cbeta.css')
    
    create_html_by_juan
    create_nav_html
    
    title = @title
    book_id = @book_id
    builder = GEPUB::Builder.new {
      language 'zh-TW'
      unique_identifier "http://www.cbeta.org/#{book_id}", 'BookID', 'URL'
      title title

      creator 'CBETA'

      contributors 'DILA'

      date Date.today.to_s
    }

    juan_dir = File.join(@temp_folder, 'juans')
    # in resources block, you can define resources by its relative path and datasource.
    # item creator methods are: files, file.
    builder.resources(:workdir => @temp_folder) {
      glob 'img/*'
      file 'cbeta.css'
      
      # this is navigation document.
      nav 'nav.xhtml'
      
      # ordered item. will be added to spine.
      ordered {
        file 'readme.xhtml'
        Dir.entries(juan_dir).sort.each do |f|
          next if f.start_with? '.'
          file "juans/#{f}"
        end
        file 'donate.xhtml'
      }
    }
    builder.book.version = @settings[:epub_version]
    builder.generate_epub(output_path)
    puts "output: #{output_path}"
  end

  def create_html_by_juan
    juans = @main_text.split(/(<juan \d+>)/)
    open = false
    fo = nil
    juan_no = nil
    fn = ''
    buf = ''
    # 一卷一檔
    juans.each do |j|
      if j =~ /<juan (\d+)>$/
        juan_no = $1.to_i
        fn = "%03d.xhtml" % juan_no
        output_path = File.join(@temp_folder, 'juans', fn)
        fo = File.open(output_path, 'w')
        open = true
        s = <<eos
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8" />
  <title>#{@title}</title>
  <link rel="stylesheet" type="text/css" href="../cbeta.css" />
</head>
<body>
<div id='body'>
eos
        fo.write(s)
        fo.write(buf)
        buf = ''
      elsif open
        fo.write(j + "\n</div><!-- end of div[@id='body'] -->\n")
        fo.write('</body></html>')
        fo.close
      else
        buf = j
      end
    end
  end
  
  def create_nav_html
    @nav_root_ol.add_child("<li><a href='donate.xhtml'>贊助資訊</a></li>")
    
    fn = File.join(@temp_folder, 'nav.xhtml')
    s = NAV_TEMPLATE % to_html(@nav_root_ol)
    File.write(fn, s)
  end
  
  def handle_anchor(e)
    if e.has_attribute?('type')
      if e['type'] == 'circle'
        return '◎'
      end
    end

    ''
  end

  def handle_app(e)
    traverse(e)
  end

  def handle_byline(e)
    r = '<p class="byline">'
    r += "<span class='lineInfo'>#{@lb}</span>"
    r += traverse(e)
    r + '</p>'
  end

  def handle_cell(e)
    doc = Nokogiri::XML::Document.new
    cell = doc.create_element('td')
    cell['rowspan'] = e['rows'] if e.key? 'rows'
    cell['colspan'] = e['cols'] if e.key? 'cols'
    cell.inner_html = traverse(e)
    to_html(cell) + "\n"
  end

  def handle_corr(e)
    traverse(e)
  end

  def handle_div(e)
    if e.has_attribute? 'type'
      @open_divs << e
      r = traverse(e)
      @open_divs.pop
      return "<div class='div-#{e['type']}'>#{r}</div>"
    else
      return traverse(e)
    end
  end

  def handle_figure(e)
    "<div class='figure'>%s</div>" % traverse(e)
  end

  def handle_g(e, mode)
    # if 有 <mapping type="unicode">
    #   if 不在 Unicode Extension C, D, E 範圍裡
    #     直接採用
    #   else
    #     預設呈現 unicode, 但仍包缺字資訊，供點選開 popup
    # else if 有 <mapping type="normal_unicode">
    #   預設呈現 normal_unicode, 但仍包缺字資訊，供點選開 popup
    # else if 有 normalized form
    #   預設呈現 normalized form, 但仍包缺字資訊，供點選開 popup
    # else
    #   預設呈現組字式, 但仍包缺字資訊，供點選開 popup
    gid = e['ref'][1..-1]
    g = @gaijis[gid]
    abort "Line:#{__LINE__} 無缺字資料:#{gid}" if g.nil?
    zzs = g['zzs']
    
    if mode == 'txt'
      return g['roman'] if gid.start_with?('SD')
      if zzs.nil?
        abort "缺組字式：#{g}"
      else
        return zzs
      end
    end

    if gid.start_with?('SD')
      case gid
      when 'SD-E35A'
        return '（'
      when 'SD-E35B'
        return '）'
      else
        return g['roman']
      end
    end
    
    if gid.start_with?('RJ')
      return g['roman']
    end
   
    default = ''
    if g.has_key?('unicode')
      if @unicode1.include?(g['unicode'])
        return g['unicode-char'] # unicode 1.1 直接用
      end
    end
    
    zzs
  end

  def handle_graphic(e)
    url = e['url']
    url.sub!(/^.*figures\/(.*)$/, '\1')
    
    src = File.join(@settings[:graphic_base], url)
    basename = File.basename(src)
    dest = File.join(@temp_folder, 'img', basename)
    FileUtils.copy(src, dest)
    
    "<img src='../img/#{basename}' />"
  end

  def handle_head(e)
    r = ''
    unless e['type'] == 'added'
      i = @open_divs.size
      r = "<p class='head' data-head-level='#{i}'>%s</p>" % traverse(e)
    end
    r
  end

  def handle_item(e)
    "<li>%s</li>\n" % traverse(e)
  end

  def handle_juan(e)
    "<p class='juan'>%s</p>" % traverse(e)
  end

  def handle_l(e)
    if @lg_type == 'abnormal'
      return traverse(e)
    end

    @in_l = true

    doc = Nokogiri::XML::Document.new
    cell = doc.create_element('div')
    cell['class'] = 'lg-cell'
    cell.inner_html = traverse(e)
    
    if @first_l
      parent = e.parent()
      if parent.has_attribute?('rend')
        indent = parent['rend'].scan(/text-indent:[^:]*/)
        unless indent.empty?
          cell['style'] = indent[0]
        end
      end
      @first_l = false
    end
    r = to_html(cell)
    
    unless @lg_row_open
      r = "\n<div class='lg-row'>" + r
      @lg_row_open = true
    end
    @in_l = false
    r
  end

  def handle_lb(e)
    # 卍續藏有 X 跟 R 兩種 lb, 只處理 X
    return '' if e['ed'] != @series

    @lb = e['n']
    r = ''
    #if e.parent.name == 'lg' and $lg_row_open
    if @lg_row_open && !@in_l
      # 每行偈頌放在一個 lg-row 裡面
      # T46n1937, p. 914a01, l 包雙行夾註跨行
      # T20n1092, 337c16, lb 在 l 中間，不結束 lg-row
      r += "</div><!-- end of lg-row -->"
      @lg_row_open = false
    end
    unless @next_line_buf.empty?
      r += @next_line_buf
      @next_line_buf = ''
    end
    r
  end

  def handle_lem(e)
    r = traverse(e)
  end

  def handle_lg(e)
    r = ''
    @lg_type = e['type']
    if @lg_type == 'abnormal'
      r = "<p class='lg-abnormal'>" + traverse(e) + "</p>"
    else
      @first_l = true
      doc = Nokogiri::XML::Document.new
      node = doc.create_element('div')
      node['class'] = 'lg'
      if e.has_attribute?('rend')
        rend = e['rend'].gsub(/text-indent:[^:]*/, '')
        node['style'] = rend
      end
      @lg_row_open = false
      node.inner_html = traverse(e)
      if @lg_row_open
        node.inner_html += '</div><!-- end of lg -->'
        @lg_row_open = false
      end
      r = "\n" + to_html(node)
    end
    r
  end

  def handle_list(e)
    "<ul>%s</ul>" % traverse(e)
  end

  def handle_milestone(e)
    r = ''
    if e['unit'] == 'juan'
      r += "</div>" * @open_divs.size  # 如果有 div 跨卷，要先結束, ex: T55n2154, p. 680a29, 跨 19, 20 兩卷
      @juan = e['n'].to_i
      r += "<juan #{@juan}>"
      @open_divs.each { |d|
        r += "<div class='#{d['type']}'>"
      }
    end
    r
  end

  def handle_mulu(e)
    return '' if e['type'] == '卷'
    
    level = e['level'].to_i
    while @current_nav.size > level
      @current_nav.pop
    end
    
    label = traverse(e, 'txt')
    @mulu_count += 1
    fn = "juans/%03d.xhtml" % @juan
    li = @current_nav.last.add_child("<li><a href='#{fn}#mulu#{@mulu_count}'>#{label}</a></li>").first
    ol = li.add_child('<ol></ol>').first
    @current_nav << ol
    "<a id='mulu#{@mulu_count}' />"
  end

  def handle_node(e, mode)
    return '' if e.comment?
    return handle_text(e, mode) if e.text?
    return '' if PASS.include?(e.name)
    r = case e.name
    when 'anchor'    then handle_anchor(e)
    when 'app'       then handle_app(e)
    when 'byline'    then handle_byline(e)
    when 'cell'      then handle_cell(e)
    when 'corr'      then handle_corr(e)
    when 'div'       then handle_div(e)
    when 'figure'    then handle_figure(e)
    when 'foreign'   then ''
    when 'g'         then handle_g(e, mode)
    when 'graphic'   then handle_graphic(e)
    when 'head'      then handle_head(e)
    when 'item'      then handle_item(e)
    when 'juan'      then handle_juan(e)
    when 'l'         then handle_l(e)
    when 'lb'        then handle_lb(e)
    when 'lem'       then handle_lem(e)
    when 'lg'        then handle_lg(e)
    when 'list'      then handle_list(e)
    when 'mulu'      then handle_mulu(e)
    when 'note'      then handle_note(e)
    when 'milestone' then handle_milestone(e)
    when 'p'         then handle_p(e)
    when 'rdg'       then ''
    when 'reg'       then ''
    when 'row'       then handle_row(e)
    when 'sic'       then ''
    when 'sg'        then handle_sg(e)
    when 't'         then handle_t(e)
    when 'tt'        then handle_tt(e)
    when 'table'     then handle_table(e)
    else traverse(e)
    end
    r
  end

  def handle_note(e)
    n = e['n']
    if e.has_attribute?('type')
      t = e['type']
      case t
      when 'equivalent'
        return ''
      when 'orig'
        return ''
      when 'orig_biao'
        return ''
      when 'orig_ke'
        return ''
      when 'mod'
        return ""
      when 'rest'
        return ''
      else
        return '' if t.start_with?('cf')
      end
    end

    if e.has_attribute?('resp')
      return '' if e['resp'].start_with? 'CBETA'
    end

    if e.has_attribute?('place') && e['place']=='inline'
      r = traverse(e)
      return "(#{r})"
    else
      return traverse(e)
    end
  end

  def handle_p(e)
    r = "<div class='p'>\n"
    r += traverse(e)
    r + "</div>\n"
  end

  def handle_row(e)
    "<tr>" + traverse(e) + "</tr>\n"
  end

  def handle_sg(e)
    '(' + traverse(e) + ')'
  end

  def handle_file(xml_fn)
    puts "read #{xml_fn}"
    @in_l = false
    @lg_row_open = false
    @mod_notes = Set.new
    @next_line_buf = ''
    @open_divs = []
    
    if @book_id.start_with? 'DA'
      @orig = nil?
    else
      @orig = @cbeta.get_canon_abbr(@book_id[0])
      abort "未處理底本: #{@book_id[0]}" if @orig.nil?
    end

    text = parse_xml(xml_fn)

    # 註標移到 lg-cell 裡面，不然以 table 呈現 lg 會有問題
    text.gsub!(/(<a class='noteAnchor'[^>]*><\/a>)(<div class="lg-cell"[^>]*>)/, '\2\1')
    
    @main_text += text    
  end

  def handle_t(e)
    if e.has_attribute? 'place'
      return '' if e['place'].include? 'foot'
    end
    r = traverse(e)

    # <tt type="app"> 不是 悉漢雙行對照
    return r if @tt_type == 'app'

    # 處理雙行對照
    i = e.xpath('../t').index(e)
    case i
    when 0
      return r + '　'
    when 1
      @next_line_buf += r + '　'
      return ''
    else
      return r
    end
  end

  def handle_tt(e)
    @tt_type = e['type']
    traverse(e)
  end

  def handle_table(e)
    "<table>" + traverse(e) + "</table>"
  end

  def handle_text(e, mode)
    s = e.content().chomp
    return '' if s.empty?
    return '' if e.parent.name == 'app'

    # cbeta xml 文字之間會有多餘的換行
    r = s.gsub(/[\n\r]/, '')

    # 把 & 轉為 &amp;
    CGI.escapeHTML(r)
  end

  def lem_note_cf(e)
    # ex: T32n1670A.xml, p. 703a16
    # <note type="cf1">K30n1002_p0257a01-a23</note>
    refs = []
    e.xpath('./note').each { |n|
      if n.key?('type') and n['type'].start_with? 'cf'
        refs << n.content
      end
    }
    if refs.empty?
      ''
    else
      '修訂依據：' + refs.join('；') + '。'
    end
  end

  def lem_note_rdg(lem)
    r = ''
    app = lem.parent
    @pass << false
    app.xpath('rdg').each { |rdg|
      if rdg['wit'].include? @orig
        s = traverse(rdg, 'back')
        s = MISSING if s.empty?
        r += @orig + s
      end
    }
    @pass.pop
    r += '。' unless r.empty?
    r
  end
  
  def sutra_init
    s = NAV_TEMPLATE % '<ol></ol>'
    @nav_doc = Nokogiri::XML(s)
    
    @nav_doc.remove_namespaces!()
    @nav_root_ol = @nav_doc.at_xpath('//ol')
    @current_nav = [@nav_root_ol]
    
    @nav_root_ol.add_child("<li><a href='readme.xhtml'>編輯說明</a></li>")
    
    @mulu_count = 0
    @main_text = ''
    @dila_note = 0
    
    FileUtils::mkdir_p File.join(@temp_folder, 'img')
    FileUtils::mkdir_p File.join(@temp_folder, 'juans')
  end

  def open_xml(fn)
    s = File.read(fn)

    if fn.include? 'T16n0657'
      # 這個地方 雙行夾註 跨兩行偈頌
      # 把 lb 移到 note 結束之前
      # 讓 lg-row 先結束，再結束雙行夾註
      s.sub!(/(<\/note>)(\n<lb n="0206b29" ed="T"\/>)/, '\2\1')
    end

    # <milestone unit="juan"> 前面的 lb 屬於新的這一卷
    s.gsub!(%r{((?:<pb [^>]+>\n?)?(?:<lb [^>]+>\n?)+)(<milestone [^>]*unit="juan"[^/>]*/>)}, '\2\1')
      
    doc = Nokogiri::XML(s)
    doc.remove_namespaces!()
    doc
  end

  def read_mod_notes(doc)
    doc.xpath("//note[@type='mod']").each { |e|
      @mod_notes << e['n']
    }
  end

  def parse_xml(xml_fn)
    @pass = [false]

    doc = open_xml(xml_fn)
        
    e = doc.xpath("//titleStmt/title")[0]
    @title = traverse(e, 'txt')
    @title = @title.split()[-1]
    
    read_mod_notes(doc)

    root = doc.root()
    body = root.xpath("text/body")[0]
    @pass = [true]

    text = traverse(body)
    text
  end
  
  def remove_empty_nav(node_list)
    node_list.each do |n|
      if n[:nav].empty?
        n.delete(:nav)
      else
        remove_empty_nav(n[:nav])
      end
    end
  end
    
  def to_html(e)
    e.to_xml(encoding: 'UTF-8', pertty: true, :save_with => Nokogiri::XML::Node::SaveOptions::AS_XML)
  end

  def traverse(e, mode='html')
    r = ''
    e.children.each { |c| 
      s = handle_node(c, mode)
      r += s
    }
    r
  end

end