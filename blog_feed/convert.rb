class Item
  attr_accessor :title, :url, :date
end

src = File.read("feed.md")

item = nil
items = []
src.lines.each { |line|
  if /^# (.+)/ =~ line
    title = $1
    items << item
    item = Item.new
    item.title = title
  elsif /^url: (.+)/ =~ line
    item.url = $1
  elsif /^date: (.+)/ =~ line
    item.date = $1
  end
}

items << item
items.compact! # 先頭の nil を除去

# pp items

require "rss"

rss =
  RSS::Maker.make("1.0") do |m|
    m.channel.title = "memo88"
    m.channel.link = "https://memo88.hatenablog.com/"
    m.channel.about = "TODO"
    m.channel.description = "TODO"

    m.items.do_sort = true

    items.each { |item|
      # rss item
      ri = m.items.new_item
      ri.link = item.url
      ri.title = item.title
      ri.date = Time.parse(item.date + " 12:00:00")
    }
  end

puts rss.to_s
