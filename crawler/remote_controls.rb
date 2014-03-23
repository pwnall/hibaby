require 'webkit_remote'
require 'webkit_remote_unstable'

# Common functions for driving a site via the WebkitRemote debugging client.
module RemoteControls

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

# Clicks a DOM element by generating mouse events.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
def hard_click_element(client, dom_node)
  box = dom_node.box_model
  xc = box.content.x.inject(0) { |a, b| a + b } / box.content.x.length
  yc = box.content.y.inject(0) { |a, b| a + b } / box.content.y.length
  client.mouse_event :move, xc, yc
  client.mouse_event :down, xc, yc, button: :left, clicks: 1
  client.mouse_event :up, xc, yc, button: :left, clicks: 1
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

# The parent of a DOM element.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @return {WebKitRemote::Client::DomNode} the given node's parent
def element_parent(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    return domNode.parentElement;
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object
  return nil unless result
  parent_node = result.dom_node
  result.release
  parent_node
end

# The parent of a DOM element.
#
# @param {WebkitRemote::Client} client
# @param {WebKitRemote::Client::DomNode} dom_node
# @return {WebKitRemote::Client::DomNode} the given node's parent
def focus_element(client, dom_node)
  js_code = <<END_JS
  function (domNode) {
    domNode.focus();
  }
END_JS
  result = client.remote_eval('window').bound_call js_code, dom_node.js_object
  result.release
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

end  # module RemoteControls
