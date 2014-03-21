require 'net/https'
require 'set'
require 'uri'

require 'webkit_remote'

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

  input_boxes =  client.dom_root.query_selector_all '[contenteditable="true"]'
  if input_boxes.length != 1
    raise 'Search box selector broken or not specific enough'
  end
  input_box = input_boxes[0]

  input_fields = client.dom_root.query_selector_all(
      'input[type="text"][placeholder*="Search"][placeholder*="people"]')
  if input_fields.length != 1
    raise 'Search box selector broken or not specific enough'
  end
  input_field = input_fields[0]

  click_element client, input_field
end


# NOTE: allow_popups is necessary to be able to click on the "search" link
client = WebkitRemote.local window: { width: 1024, height: 768 }
fb_login client, 'leemoh@mit.edu', 'moresparkles'

