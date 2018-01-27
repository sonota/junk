#!/usr/bin/env ruby
# coding: utf-8

require "strscan"

class MyStringScanner < StringScanner

  attr_reader :pos_bom

  def initialize(str)
    super(str)
    @pos_bom = 0 # beginning of match
  end

  def byteslice(pos_from, pos_to)
    string().byteslice(pos_from, pos_to - pos_from)
  end

  def scan(re)
    @pos_bom = pos # マッチを行う前に開始位置を保存
    super(re)
  end
end


def str_rest_bytesize(rest)
  pos = 0
  while pos < rest.size
    c = rest[pos]
    case c
    when "\\"
      # 次の文字まで読み飛ばす
      pos += 2
    when "'"
      break
    else
      pos += 1
    end
  end

  rest[0..pos].bytesize
end

def block_cmt_rest_bytesize(rest)
  pos = 0
  while pos < rest.size - 1
    c = rest[pos]
    case c
    when "\\"
      # 次の文字まで読み飛ばす
      pos += 2
    when "*"
      if rest[pos+1] == "/"
        pos += 1
        break
      else
        pos += 1
      end
    else
      pos += 1
    end
  end
  rest[0..pos].bytesize
end

def main(sql)
  ss = MyStringScanner.new(sql)
  pos_prev_eom = ss.pos # previous end of match
  result = ""

  while not ss.eos?
    case
    when ss.scan( /'/ )
      result += ss.byteslice(pos_prev_eom, ss.pos_bom)

      size = str_rest_bytesize(ss.rest)

      str_rest = ss.byteslice(ss.pos, ss.pos + size)
      result += "'" + str_rest
      ss.pos += size

      pos_prev_eom = ss.pos

    when ss.scan( /--(.*)/ )
      result += ss.byteslice(pos_prev_eom, ss.pos_bom)

      pos_prev_eom = ss.pos

    when ss.scan( /\/\*/ )
      result += ss.byteslice(pos_prev_eom, ss.pos_bom)

      size = block_cmt_rest_bytesize(ss.rest)

      ss.pos += size

      pos_prev_eom = ss.pos

    else
      ss.getch

    end
  end

  if pos_prev_eom < ss.string.bytesize
    result += ss.byteslice(pos_prev_eom, ss.string.bytesize)
  end

  result
end

def main_io(io)
  removed = main(io.read)
  print removed
end

if $0 == __FILE__
  main_io $stdin
end
