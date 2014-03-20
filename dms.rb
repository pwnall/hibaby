require 'net/https'
require 'set'
require 'uri'

require 'webkit_remote'

# Inputs text in an input box.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @param {String} text
def input_text(client, dom_node, text)
  # TODO(pwnall): consider injecting keystrokes
  js_code = <<END_JS
  function (input, text) {
    input.value = text;
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object,
                                                   text
  result.release
end

# Clicks a DOM element.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
def click_element(client, dom_node)
  # NOTE: not using the "new Event"-style creation because DMS overwrites
  #       window.Event with its own contraption
  js_code = <<END_JS
  function (domNode) {
    var rect = domNode.getBoundingClientRect();
    var clientX = parseInt(domNode.clientWidth / 2);
    var clientY = parseInt(domNode.clientHeight / 2);
    var screenX = parseInt(rect.left + rect.width / 2);
    var screenY = parseInt(rect.top + rect.height / 2);
    var button = 0;  // Left mouse button.

    var event = document.createEvent("MouseEvents");
    event.initMouseEvent(
      "click", true, true, window, 1,
      screenX, screenY, clientX, clientY,
      false, false, false, false,  // Ctrl, Alt, Shift, Meta
      button, null
    );
    domNode.dispatchEvent(event);
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object
  result.release
end

# The coordinates of a bounding box for an element.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @return {Hash} has keys :height, :width, :top, :left and number values
def bounding_box(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    return domNode.getBoundingClientRect();
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object

  box = {
    width: result.properties['width'].value,
    height: result.properties['height'].value,
    top: result.properties['top'].value,
    left: result.properties['left'].value,
  }
  result.release
  box
end

# True if a DOM element is on the page, false if it is outside the page.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @return {Boolean} true if an element is positioned within the page's
#     boundaries, and false if it is off; this is usually the case for non-UI
#     elements
def is_on_page(client, dom_node)
  box = bounding_box client, dom_node
  if box[:left] + box[:width] <= 0 || box[:top] + box[:height] <= 0
    return false
  end
  # TODO(pwnall): bottom & right tests require page metrics
  true
end

# The text inside a DOM element.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @return {String} the text inside the element; this is the value of the
#     textContent property (also known as innerText)
def element_text_content(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    return domNode.textContent;
  }
END_JS
  client.remote_eval('window').bound_call js_code, dom_node.js_object
  # NOTE: this returns a String, we don't need to release it
end

# Scrolls the browser view in such a way that a DOM element is in the viewport.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
def scroll_to(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    domNode.scrollIntoView();
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object
  result.release
end

# Logs into the DMS site.
#
# This assumes the user is not logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {String} email
# @param {String} password
def dms_login(client, email, password)
  client.page_events = true
  client.navigate_to 'https://datemyschool.com'
  client.wait_for type: WebkitRemote::Event::PageLoaded

  login_link = client.dom_root.query_selector '#login-link'
  click_element client, login_link

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

# Makes a search on the DMS site.
#
# This assumes a user is logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {Hash<String, String>} criteria the search criteria, e.g.
#     "Schools": "MIT"
def dms_issue_search(client, criteria)
  client.page_events = true
  client.navigate_to 'https://datemyschool.com/'
  client.wait_for type: WebkitRemote::Event::PageLoaded

  search_links = client.dom_root.query_selector_all 'a[href*="search"]'
  search_link = search_links.find do |link|
    /Browse/ =~ link.outer_html && is_on_page(client, link)
  end
  unless search_link
    raise 'Failed to find the search link'
  end
  click_element client, search_link
  client.wait_for type: WebkitRemote::Event::PageLoaded
  client.clear_all

  advanced_arrows = client.dom_root.query_selector_all '.open-close-part a'
  unless advanced_arrows.length == 1
    raise 'Failed to find the advanced search arrow'
  end
  advanced_arrow = advanced_arrows.first
  click_element client, advanced_arrow

  dropdown_containers = {}
  client.dom_root.query_selector_all('.filter-field').each do |container|
    label = container.query_selector 'label'
    next if label.nil?
    dropdown_containers[element_text_content(client, label)] = container
  end

  criteria.each do |category, category_choice|
    # Semi-generic code for working a "fancy" dropdown.
    dropdown = dropdown_containers[category]
    click_element client, dropdown.query_selector('.arrow')
    dropdown_select = dropdown.query_selector('select')
    dropdown_options = {}
    dropdown_select.query_selector_all('option').each do |option|
      text = element_text_content(client, option)
      dropdown_options[text] = option.attributes['value'].strip
    end
    # The "fancy" dropdown options aren't in the container's tree.
    option_id = dropdown_options[category_choice]
    unless option_id
      raise "Failed to find option #{category_choice} for category #{category}."
    end
    dropdown_li = client.dom_root.
        query_selector_all("li[data-id=#{option_id.inspect}]").find do |li|
      element_text_content(client, li).strip == category_choice
    end
    if dropdown_li.nil?
      raise "Failed to find <li> for option #{category_choice} in #{category}."
    end
    click_element client, dropdown_li
  end

  search_button = client.dom_root.query_selector(
      'form[action*="search"] input[type="submit"]')
  click_element client, search_button
  client.page_events = false
  client.clear_all
end

# Scrolls the DMS search screen to the bottom, so it loades more matches.
#
# @param {WebkitRemote::Client} client
# @return {Boolean} true if scrolling to the bottom returned more matches,
#     false otherwise
def dms_search_scroll(client)
  last_page_div = client.dom_root!.
      query_selector_all('.browse[data-page-num]').last
  last_page_num = last_page_div.attributes['data-page-num'].strip

  scroll_to client, last_page_div
  client.clear_all

  # HACK(pwnall): should use a DOM breakpoint or some network listener instead
  #     of this hacked up approach
  300.times do
    sleep 2
    new_last_page_div = client.dom_root.query_selector_all(
        '.browse[data-page-num]').last
    new_last_page_num = new_last_page_div.attributes['data-page-num'].strip
    return true if new_last_page_num != last_page_num
  end
  false
end

# Extracts results from a DMS page div.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} page_div a DOM node containing a
#     "page" of search results
def dms_get_results(client, page_div)
  results = []
  page_div.query_selector_all('div[data-user-id]').each do |result_div|
    profile_id = result_div.attributes['data-user-id'].strip
    profile_link = page_div.query_selector(
        "a[href*=\"profile\"][href*=#{profile_id.inspect}")
    if profile_link
      profile_url = profile_link.attributes['href']
    else
      profile_url = nil
    end

    picture_img = result_div.query_selector(
        "img[src*=pics][src*=#{profile_id.inspect}]")
    if picture_img
      picture_url = picture_img.attributes['src']
    else
      picture_url = nil
    end

    details = {}
    [
      [:username, '.nickname .username'],
      [:age, '.basics .age'],
      [:uni, '.uni'],
      [:school, '.school'],
    ].each do |detail|
      key = detail[0]
      selector = detail[1]
      detail_element = result_div.query_selector(".profile-info #{selector}")
      if detail_element
        details[key] = element_text_content client, detail_element
      end
    end

    if picture_img
      results << {
        id: profile_id,
        url: profile_url,
        pic: picture_url,
        details: details,
      }
    end
  end
  results
end

# Makes a search on the DMS site.
#
# This assumes a user is logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {Hash<String, String>} criteria the search criteria, e.g.
#     "Schools": "MIT"
# @yield
def dms_search(client, criteria)
  dms_issue_search client, criteria

  seen_pages = Set.new

  done_scrolling = false
  loop do
    page_divs = client.dom_root.query_selector_all('.browse[data-page-num]')
    3.times do
      begin
        page_divs.each do |page_div|
          page_num = page_div.attributes['data-page-num'].strip
          next if seen_pages.include?(page_num)

          page_results = dms_get_results client, page_div
          page_results.each do |page_result|
            yield page_result
          end

          seen_pages << page_num
        end
        break
      rescue RuntimeError
        # The DOM got modified as we were scanning the page.
      end
    end

    break if done_scrolling
    done_scrolling = true unless dms_search_scroll(client)
  end
end

# NOTE: allow_popups is necessary to be able to click on the "search" link
client = WebkitRemote.local window: { width: 1024, height: 768 }
dms_login client, 'leemoh@mit.edu', 'moresparkles'
dms_search client, 'Schools' => ARGV[0] do |result|
  File.write "#{result[:id]}.json", JSON.dump(result)
  pic_result = Net::HTTP.get URI.parse(result[:pic])
  File.binwrite "#{result[:id]}.jpg", pic_result
end
client.close_browser
