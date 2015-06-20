require 'net/https'
require 'set'
require 'uri'

require 'webkit_remote'
require 'webkit_remote_unstable'

require_relative 'remote_controls.rb'
include RemoteControls

# Logs into the DMS site.
#
# This assumes the user is not logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {String} email
# @param {String} password
def fb_login(client, email, password)
  client.page_events = true
  client.navigate_to 'https://facebook.com'
  client.wait_for type: WebkitRemote::Event::PageLoaded

  login_forms = client.dom_root.query_selector_all 'form[action*="login"]'
  if login_forms.length != 1
    raise 'Login form selector broken or not specific enough'
  end
  login_form = login_forms.first

  email_input = login_form.query_selector 'input[type="text"]'
  input_text client, email_input, email

  password_input = login_form.query_selector 'input[type="password"]'
  input_text client, password_input, password

  submit_button = login_form.query_selector 'input[type="submit"]'
  click_element client, submit_button

  client.wait_for type: WebkitRemote::Event::PageLoaded
  client.page_events = false
  client.clear_all
end

# Logs into the DMS site.
#
# This assumes the user is not logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {String} query_string
def fb_issue_search(client, query_string)
  client.page_events = true
  client.navigate_to 'https://facebook.com'
  client.wait_for type: WebkitRemote::Event::PageLoaded

  feed_links = client.dom_root.query_selector_all 'a[href*="sk=nf"]'
  if feed_links.length != 1
    raise 'Newsfeed link selector broken or not specific enough'
  end
  feed_link = feed_links.first
  click_element client, feed_link
  client.wait_for type: WebkitRemote::Event::PageLoaded
  client.clear_all

  client.reload
  client.wait_for type: WebkitRemote::Event::PageLoaded
  client.clear_all

  # Fire the search shortcut /
  client.key_event :down, vkey: 0x11, key_id: 'Control', system_key: true
  client.key_event :down, vkey: 0x12, key_id: 'Alt', modifiers: [:ctrl], system_key: true
  client.key_event :up, vkey: 0x12, key_id: 'Alt', modifiers: [:ctrl], system_key: true
  client.key_event :up, vkey: 0x11, key_id: 'Control', system_key: true
  sleep 0.2
  client.key_event :down, vkey: 0x2F, key_id: 'U+002F'
  client.key_event :char, text: '/'
  client.key_event :up, vkey: 0x2F, key_id: 'U+002F'
  sleep 0.1

=begin
  input_boxes = client.dom_root.query_selector_all '[contenteditable="true"]'
  if input_boxes.length != 1
    raise 'Search box selector broken or not specific enough'
  end
  input_box = input_boxes[0]
  input_box.focus

  input_control = input_box
  until /(^|\s)textInput(\s|$)/ =~ input_control.attributes['class']
    input_control = element_parent client, input_control
  end
  input_control.query_selector_all('*').each do |child|
    click_element client, child
  end
  hard_click_element client, input_control
=end

  client.key_event :down, vkey: 0x2F, key_id: 'U+002F'
  client.key_event :char, text: '/'
  client.key_event :up, vkey: 0x2F, key_id: 'U+002F'
  sleep 0.1

  query_string.each_char do |char|
    # TODO(pwnall): better method for vkeys
    vkey_code = char.upcase.ord
    key_id = "U+%04X" % vkey_code
    p [char, vkey_code, key_id]
    client.key_event :down, vkey: vkey_code, key_id: key_id
    client.key_event :char, text: char
    client.key_event :up, vkey: vkey_code, key_id: key_id
    sleep 0.1
  end
  sleep 0.1
  client.key_event :down, vkey: 0x09, key_id: 'U+0009'
  client.key_event :up, vkey: 0x09, key_id: 'U+0009'
  sleep 2
  client.key_event :down, vkey: 0x13, key_id: 'Enter'
  client.key_event :up, vkey: 0x13, key_id: 'Enter'

  #input_fields = client.dom_root.query_selector_all(
  #    'input[type="text"][placeholder*="Search"][placeholder*="people"]')
  #if input_fields.length != 1
  #  raise 'Search box selector broken or not specific enough'
  #end
  #input_field = input_fields[0]
end

# Scrolls the DMS search screen to the bottom, so it loades more matches.
#
# @param {WebkitRemote::Client} client
# @return {Boolean} true if scrolling to the bottom returned more matches,
#     false otherwise
def fb_search_scroll(client)
  page_divs = client.dom_root!.
      query_selector_all('[id*=BrowseScrollingPagerContainer]').length

  10.times do
    footer_div = client.dom_root!.query_selector '#pageFooter'
    scroll_to client, footer_div
    client.clear_all

    # HACK(pwnall): should use a DOM breakpoint or some network listener
    #     instead of this hacked up approach
    180.times do
      sleep 2
      new_page_divs = client.dom_root!.
          query_selector_all('[id*=BrowseScrollingPagerContainer]').length
      p [page_divs, new_page_divs]
      return true if page_divs != new_page_divs
    end
    false
  end
end

# Extracts results from a FB page div.
def fb_get_results(client, page_div)
  results = []

  images = page_div.query_selector_all(
      'a[href^="https://www.facebook.com/"][href*="search"] ' +
      'img[src*="profile"]')
  images.each do |image|
    image_src = image.attributes['src']
    link = image
    until element_matches(client, link, 'a')
      link = element_parent client, link
    end
    link_href = link.attributes['href']
    if match = (/^https:\/\/www\.facebook\.com\/([^\/\?]+)\?/i).
        match(link_href)
      profile_name = match[1]
    else
      # Discard profiles without usernames.
      # TODO(pwnall): consider accepting profiles with IDs, if they ever come
      #               up
      p link_href
      next
    end
    results << {
      name: profile_name,
      pic: image_src,
      url: link_href,
    }
  end
  results
end

# Makes a search on the FB site.
#
# This assumes a user is logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {Hash<String, String>} criteria the search criteria, e.g.
#     "Schools": "MIT"
# @yield {Hash<Symbol, Object>} each search result
def fb_search(client, query_string)
  # TODO(pwnall): figure out why this doesn't work
  #fb_issue_search client, query_string

  client.page_events = true
  client.navigate_to 'https://www.facebook.com/search/126533127390327/students/females/intersect'
  client.wait_for type: WebkitRemote::Event::PageLoaded
  client.clear_all

  # Non-scrolling results.
  ['#BrowseResultsContainer', '#browse_result_below_fold'].each do |selector|
    page_div = client.dom_root.query_selector selector
    fb_get_results(client, page_div).each do |result|
      yield result
    end
  end

  # Scrolling results.
  seen_pages = Set.new
  loop do
    break unless fb_search_scroll(client)
    page_divs = client.dom_root.query_selector_all(
        '[id*=BrowseScrollingPagerContainer]')
    page_divs.each do |page_div|
      page_id = page_div.attributes['id']
      next if seen_pages.include?(page_id)

      fb_get_results(client, page_div).each do |result|
        yield result
      end

      seen_pages << page_id
    end
  end
end

# NOTE: allow_popups is necessary to be able to click on the "search" link
client = WebkitRemote.local window: { width: 1024, height: 768 },
  chrome_binary: '/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary'
#  chrome_binary: '/Users/pwnall/chromium/src/out/Debug/Chromium.app/Contents/MacOS/Chromium'
fb_login client, 'leemoh@mit.edu', 'moresparkles'

query = 'female students at massachusetts institute of technology'
fb_search client, query do |result|
  File.write "#{result[:name]}.json", JSON.dump(result)
  pic_result = Net::HTTP.get URI.parse(result[:pic])
  File.binwrite "#{result[:name]}.jpg", pic_result
end

client.close
