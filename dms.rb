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
# @return {String} the text inside the element; this is the value of the
#     textContent property (also known as innerText)
def element_text_content(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    return domNode.textContent;
  }
END_JS
  client.remote_eval('window').bound_call js_code, dom_node.js_object
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
# This assumes the user is not logged into the site.
#
# @param {WebkitRemote::Client} client
# @param {String} email
# @param {String} password
def dms_search(client, email, password)
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

  category = 'Schools'
  category_choice = 'MIT'

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

  search_button = client.dom_root.query_selector(
      'form[action*="search"] input[type="submit"]')
  click_element client, search_button
end


# NOTE: allow_popups is necessary to be able to click on the "search" link
client = WebkitRemote.local window: { width: 1024, height: 768 }
dms_login client, 'leemoh@mit.edu', 'moresparkles'
