module RedCloth::Formatters::Text
  include RedCloth::Formatters::Base
  
  [:h1, :h2, :h3, :h4, :h5, :h6, :p, :pre, :div].each do |m|
    define_method(m) do |opts|
      "#{opts[:text]}\n"
    end
  end
  
  [:strong, :code, :em, :i, :b, :ins, :sup, :sub, :span, :cite].each do |m|
    define_method(m) do |opts|
      opts[:block] = true
      "#{opts[:text]}"
    end
  end
  
  def hr(opts)
    "---\n"
  end
  
  def acronym(opts)
    opts[:block] = true
    "#{caps(:text => opts[:text])}"
  end
  
  def caps(opts)
    if no_span_caps
      opts[:text]
    else
      opts[:class] = 'caps'
      span(opts)
    end
  end
  
  def del(opts)
    opts[:block] = true
    "#{opts[:text]}"
  end
  
  [:ol, :ul].each do |m|
    define_method("#{m}_open") do |opts|
      opts[:block] = true
      "#{"\n" if opts[:nest] > 1}#{"\t" * (opts[:nest] - 1)}"
    end
    define_method("#{m}_close") do |opts|
      "#{li_close}#{"\t" * (opts[:nest] - 1)}#{"\n" if opts[:nest] <= 1}"
    end
  end
  
  def li_open(opts)
    # Delete attributes that only apply to ul/ol
    opts.delete(:align)
    opts.delete(:class)
    opts.delete(:style)
    opts.delete(:lang)
    "#{li_close unless opts.delete(:first)}#{"\t" * opts[:nest]}#{opts[:text]}"
  end
  
  def li_close(opts=nil)
    "\n"
  end
  
  def dl_open(opts)
    opts[:block] = true
    ""
  end
  
  def dl_close(opts=nil)
    "\n"
  end
  
  [:dt, :dd].each do |m|
    define_method(m) do |opts|
      "\t#{opts[:text]}\n"
    end
  end
  
  def td(opts)
    tdtype = opts[:th] ? 'th' : 'td'
    "\t\t#{opts[:text]}\n"
  end
  
  def tr_open(opts)
    "\t\n"
  end
  
  def tr_close(opts)
    "\t\n"
  end
  
  def table_open(opts)
    ""
  end
  
  def table_close(opts)
    ""
  end
  
  def bc_open(opts)
    opts[:block] = true
    ""
  end
  
  def bc_close(opts)
    "\n"
  end
  
  def bq_open(opts)
    opts[:block] = true
    cite = opts[:cite] ? " cite=\"#{ escape_attribute opts[:cite] }\"" : ''
    "\n"
  end
  
  def bq_close(opts)
    "\n"
  end
  
  def link(opts)
    "#{opts[:name]} (#{opts[:href]})"
  end
  
  def image(opts)
    opts.delete(:align)
    opts[:alt] = opts[:title]
    ""
  end
  
  def footno(opts)
    opts[:id] ||= opts[:text]
    ""
  end
  
  def fn(opts)
    no = opts[:id]
    opts[:id] = "fn#{no}"
    opts[:class] = ["footnote", opts[:class]].compact.join(" ")
    ""
  end
  
  def snip(opts)
    "\n#{opts[:text]}\n"
  end
  
  def quote1(opts)
    "\"#{opts[:text]}\""
  end
  
  def quote2(opts)
    "\"#{opts[:text]}\""
  end
  
  def multi_paragraph_quote(opts)
    "\"#{opts[:text]}"
  end
  
  def ellipsis(opts)
    "#{opts[:text]}..."
  end
  
  def emdash(opts)
    "--"
  end
  
  def endash(opts)
    " - "
  end
  
  def arrow(opts)
    "->"
  end
  
  def dim(opts)
    opts[:text].gsub!('x', '&#215;')
    opts[:text].gsub!("'", '&#8242;')
    opts[:text].gsub!('"', '&#8243;')
    opts[:text]
  end
  
  def trademark(opts)
    "(tm)"
  end
  
  def registered(opts)
    "(r)"
  end
  
  def copyright(opts)
    "(c)"
  end
  
  def entity(opts)
    ""
  end
  
  def amp(opts)
    "&"
  end
  
  def gt(opts)
    ">"
  end
  
  def lt(opts)
    "<"
  end
  
  def br(opts)
    "\n"
  end
  
  def quot(opts)
    "\""
  end
  
  def squot(opts)
    "'"
  end
  
  def apos(opts)
    "'"
  end
  
  def html(opts)
    "#{opts[:text]}\n"
  end
  
  def html_block(opts)
    "#{opts[:text]}\n"
  end
  
  def notextile(opts)
    "#{opts[:text]}\n"
  end
  
  def inline_html(opts)
    "#{opts[:text]}" # nil-safe
  end
  
  def ignored_line(opts)
    opts[:text] + "\n"
  end
  
private
  
  # escapement for regular HTML (not in PRE tag)
  def escape(text)
    html_esc(text)
  end
 
  # escapement for HTML in a PRE tag
  def escape_pre(text)
    html_esc(text, :html_escape_preformatted)
  end
  
  # escaping for HTML attributes
  def escape_attribute(text)
    html_esc(text, :html_escape_attributes)
  end
  
  def after_transform(text)
    text.chomp!
  end
  
  
  def before_transform(text)
    clean_html(text) if sanitize_html
  end
  
  # HTML cleansing stuff
  BASIC_TAGS = {
      'a' => ['href', 'title'],
      'img' => ['src', 'alt', 'title'],
      'br' => [],
      'i' => nil,
      'u' => nil, 
      'b' => nil,
      'pre' => nil,
      'kbd' => nil,
      'code' => ['lang'],
      'cite' => nil,
      'strong' => nil,
      'em' => nil,
      'ins' => nil,
      'sup' => nil,
      'sub' => nil,
      'del' => nil,
      'table' => nil,
      'tr' => nil,
      'td' => ['colspan', 'rowspan'],
      'th' => nil,
      'ol' => ['start'],
      'ul' => nil,
      'li' => nil,
      'p' => nil,
      'h1' => nil,
      'h2' => nil,
      'h3' => nil,
      'h4' => nil,
      'h5' => nil,
      'h6' => nil, 
      'blockquote' => ['cite'],
      'notextile' => nil
  }
  
  # Clean unauthorized tags.
  def clean_html( text, allowed_tags = BASIC_TAGS )
    text.gsub!( /<!\[CDATA\[/, '' )
    text.gsub!( /<(\/*)([A-Za-z]\w*)([^>]*?)(\s?\/?)>/ ) do |m|
      raw = $~
      tag = raw[2].downcase
      if allowed_tags.has_key? tag
        pcs = [tag]
        allowed_tags[tag].each do |prop|
          ['"', "'", ''].each do |q|
            q2 = ( q != '' ? q : '\s' )
            if raw[3] =~ /#{prop}\s*=\s*#{q}([^#{q2}]+)#{q}/i
              attrv = $1
              next if (prop == 'src' or prop == 'href') and not attrv =~ %r{^(http|https|ftp):}
              pcs << "#{prop}=\"#{attrv.gsub('"', '\\"')}\""
              break
            end
          end
        end if allowed_tags[tag]
        "<#{raw[1]}#{pcs.join " "}#{raw[4]}>"
      else # Unauthorized tag
        if block_given?
          yield m
        else
          ''
        end
      end
    end
  end
end