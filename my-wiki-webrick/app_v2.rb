load "./lib.rb"
load "./mal.rb"

load "./lib/vcs_git.rb"
$vcs = VcsGit.new

class Routing
  def initialize
    @routes = []
  end

  def add(method, pattern, block)
    @routes << {
      pattern: pattern,
      method: method,
      block: block
    }
  end

  def match(method, path_target)
    @routes.each do |route|
      path_pattern = route[:pattern]
      parts_p = path_pattern.split("/", -1)
      parts_t = path_target.split("/", -1)
      size = [
        parts_p.size,
        parts_t.size
      ].max

      params = {}
      matched = true

      (0...size).each do |i|
        part_p = parts_p[i]
        part_t = parts_t[i]

        if part_p.nil?
          matched = false
          break
        elsif part_p.start_with?(":")
          key = part_p[1..-1]
          params[key] = part_t
        else
          if part_t != part_p
            matched = false
            break
          end
        end
      end

      if method != route[:method]
        matched = false
      end

      if matched
        return [route, params]
      end
    end

    nil
  end

  def match?(method, path_target)
    match(method, path_target)
  end

  def dispatch(route, req, params)
    params = params.merge(to_params(req))

    route[:block].call(req, params)
  end
end

$routing = Routing.new

def get(path, &block)
  $routing.add("GET", path, block)
end

def patch(path, &block)
  $routing.add("PATCH", path, block)
end

get "/foo/:a/:b" do |req, params|
  [
    200,
    { "Content-Type" => "text/html" },
    <<~HTML
<pre>
FOO
----
#{req.query.pretty_inspect}
----
#{params}
</pre>
    HTML
  ]
end

def render(path)
  view_dir = File.join(JJSIKI_DIR, "app/views/")

  [
    File.read(File.join(view_dir, "_header.html")),
    File.read(File.join(view_dir, "#{path}.html")),
    File.read(File.join(view_dir, "_footer.html"))
  ].join("")
end

def _render_nofile(name, js_path, context)
  view_dir = File.join(JJSIKI_DIR, "app/views/")

  body = <<~EOB
    <div id="tree_builder_container"></div>
    <script src="/js#{js_path}.js"></script>
  EOB

  [
    File.read(File.join(view_dir, "_header.html")),
    body,
    File.read(File.join(view_dir, "_footer.html"))
  ].join("")
end

def to_params(req)
  params = {}
  req.query.each { |k, v|
    params[k.to_sym] = v
  }
  params
end

def redirect_to(path)
  <<~HTML
    <script>
      location.href = "#{path}";
    </script>
  HTML
end

def to_api_triple(json)
  [
    200,
    { "Content-Type" => "application/json" },
    json
  ]
end

# --------------------------------

def add_to_recent_changes(id, title, type)
  path = data_path("recent_changes.json")

  unless File.exist?(path)
    open(path, "wb"){|f| f.puts "[]" }
  end

  changes = read_json(path)
  d = Time.now

  changes2 = changes.select do |change|
    change["id"] != id
  end

  changes2.unshift(
    {
      "id"         => id,
      "title"      => title,
      "timestamp"  => d.strftime("%s_%F_%T"),
      "type"       => type
    }
  )

  if changes2.size > 200
    changes2.pop()
  end

  open(path, "wb") { |f| f.puts JSON.pretty_generate(changes2) }
end

# --------------------------------
# create page

get "/page/new" do |req, params|
  wiki = Wiki.new

  new_id = wiki.max_page_id + 1
  new_title = "(page #{new_id})"

  page = Page.new(new_id)
  page.src = "TODO"
  page.title = new_title
  page.save()

  wiki.id_title_map_put(new_id, new_title)

  add_to_recent_changes(page.id, page.title, "create")

  [
    200,
    { "Content-Type" => "text/html" },
    redirect_to("/page/#{new_id}")
  ]
end

# --------------------------------

get "/page/:id" do |req, params|
  body = render("page/show")

  [
    200,
    { "Content-Type" => "text/html" },
    body
  ]
end

get "/api/page/:id" do |req, params|
  wiki = Wiki.new

  print_stderr(
    [
      34, 
      req.query
    ].pretty_inspect
  )

  page_id = params["id"].to_i

  link_map_inv = read_page_link_interted()

  json =
    _api_v2(params) do |_params|
      {
        title: Page.get_title(page_id),
        src: Page.get_src(page_id),
        page_id_title_map: wiki.id_title_map,
        inverted_links: link_map_inv[page_id.to_s] || []
      }
    end

  to_api_triple(json)
end

# --------------------------------
# edit form

get "/page/:id/edit" do |req, params|
  page_id = params["id"].to_i
  file_path = data_path("page/#{page_id}.txt")

  body = render("page/edit")

  [
    200,
    { "Content-Type" => "text/html" },
    body
  ]
end

def parse_range(range_str)
  xs = range_str.split(",")
  Range.new(xs[0].to_i, xs[1].to_i)
end

def get_range_from_params(_params)
  range_all = Range.new(1, 1_000_000)

  if _params.key?(:range)
    if _params[:range].nil?
      range_all
    else
      parse_range(_params[:range])
    end
  else
    range_all
  end
end

get "/api/page/:id/edit" do |req, params|
  wiki = Wiki.new

  print_stderr(
    [
      34, 
      req.query
    ].pretty_inspect
  )

  page_id = params["id"].to_i

  link_map_inv = read_page_link_interted()

  json =
    _api_v2(params) do |_params|
      range = get_range_from_params(_params)
      print_stderr(
        "range (#{range.inspect})",
        label: "178"
      )

      page = Page.new(page_id)
      page.load()

      {
        title: Page.get_title(page_id),
        src: page.src_for_range(range)
      }
    end

  to_api_triple(json)
end

# --------------------------------

patch "/api/page/:id" do |req, params|
  wiki = Wiki.new

  print_stderr(
    [
      req.query
    ].pretty_inspect,
    label: "api_page_update:199"
  )

  page_id = params["id"].to_i

  json =
    _api_v2(params) do |_params|
      range = get_range_from_params(_params)

      src = _params[:src].gsub("\r\n", "\n")

      page = Page.new(page_id)
      page.load()

      page.title = _params[:title]
      page.merge_edited!(range, src)

      page.save()

      wiki = Wiki.new
      wiki.id_title_map_put(page.id.to_s, page.title)

      # TODO 変更がないのにコミットしようとするとエラーになる
      $vcs.commit(
        "edit {title}",
        {
          remote_addr: "{remote_address}", # TODO
          user_name: "{user_name}", # TODO params[:user_name],
          src: src,
          old_src: "{old_src}", # TODO
          id: page_id
        }
      )

      add_to_recent_changes(page_id, _params[:title], "update")

      {}
    end

  to_api_triple(json)
end

# --------------------------------

get "/search" do |req, params|
  html = _render_nofile("search", "/page_search", {})
  [
    200,
    { "Content-Type" => "text/html" },
    html
  ]
end

get "/api/search" do |req, params|
  wiki = Wiki.new

  json =
    _api_v2(params) do |_params|
      {
        id_title_map: wiki.id_title_map
      }
    end

  to_api_triple(json)
end

get "/api/search_grep" do |req, params|
  wiki = Wiki.new

  json =
    _api_v2(params) do |_params|
      pages = Searcher.grep(_params[:q])

      pages.each{|page|
        page[:title] = wiki.id_title_map[page[:id].to_s]
      }

      {
        pages: pages
      }
    end

  to_api_triple(json)
end

get "/api/search_grep_file" do |req, params|
  wiki = Wiki.new

  json =
    _api_v2(params) do |_params|
      lines = Searcher.grep_file(
        _params[:page_id],
        _params[:q]
      )

      { lines: lines }
    end

  to_api_triple(json)
end

# --------------------------------

get "/recent_changes" do |req, params|
  title = "最近更新されたページ"
  html =
    _render_nofile(
      "recent_changes",
      "/page_recent_changes",
      {}
    )

  [
    200,
    { "Content-Type" => "text/html" },
    html
  ]
end

get "/api/recent_changes" do |req, params|
  # var title = "最近更新されたページ";
  # var changes = read_json(APP_ROOT + "/recent_changes.json");

  # res.send(render("recent_changes", {
  #   pageTitle: title
  #   ,title: title
  #   ,changes: changes
  # }));

  changes = read_json(
    data_path("recent_changes.json")
  )

  json =
    _api_v2(params) do |_params|
      {
        changes: changes
      }
    end

  to_api_triple(json)
end

# --------------------------------

patch "/api/page/:id/links" do |req, params|
  page_id = params["id"].to_i

  json =
    _api_v2(params) do |_params|
      p_e [488, page_id, _params]

      path = data_path("page_link.json")
      path_inv = data_path("page_link_inverted.json")

      link_map =
        if File.exist?(path)
          read_json(path)
        else
          {} # 初回
        end

      link_map[page_id.to_s] = _params[:dest_ids]

      File.open(path, "wb") { |f| f.print JSON.generate(link_map) }

      # 転置インデックスを更新
      link_map_inv = {}
      link_map.each { |src, dest_ids|
        src_id = src.to_i
        dest_ids.each { |dest_id|
          link_map_inv[dest_id] ||= []
          link_map_inv[dest_id] << src_id
        }
      }

      File.open(path_inv, "wb") { |f| f.print JSON.generate(link_map_inv) }

      {}
    end

  to_api_triple(json)
end

# --------------------------------

def set_res(res, triple)
  st, info, body = triple
  res.status = st
  if info.key?("Content-Type")
    res.content_type = info["Content-Type"]
  end
  res.body = body
end

def send_file(req)
  pub_dir = 
    File.join(
      CONFIG["jjsiki_dir"],
      "app/public"
    )
  path = File.join(pub_dir, req.path)
  if File.exist?(path)
    [
      200,
      {},
      File.read(path)
    ]
  else
    [
      404,
      {},
      "not found #{req.path}"
    ]
  end
end

def do_get(req, res)
  triple =
    if $routing.match?("GET", req.path)
      route, params = $routing.match("GET", req.path)
      $routing.dispatch(route, req, params)
    else
      send_file(req)
    end

  set_res(res, triple)
end

def get_method(req)
  if req.query.key?("_method")
    req.query["_method"]
  else
    "POST"
  end 
end

def invalid_req
  [
    500, # TODO クライアントのせいなので 500 ではない
    { "Content-Type" => "text/plain" },
    "invalid req"
  ]
end

def do_post(req, res)
  print_stderr(
    [
      "req.path (#{req.path})",
      "method (POST)",
      "req.query (#{ req.query })"
    ].join("\n"),
    label: "do_post"
  )

  method = get_method(req)

  triple =
    if $routing.match?(method, req.path)
      route, params = $routing.match(method, req.path)
      $routing.dispatch(route, req, params)
    else
      [
        404, # TODO 適切なものにする
        { "Content-Type" => "text/plain" },
        "not found #{req.path}"
      ]
    end

  set_res(res, triple)
end
