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
  5.times do
    page_divs = client.dom_root!.
        query_selector_all('.browse[data-page-num]').length

    footer_div = client.dom_root!.query_selector '.bottomBar'
    scroll_to client, footer_div
    client.clear_all

    # HACK(pwnall): should use a DOM breakpoint or some network listener
    #     instead of this hacked up approach
    100.times do
      sleep 2
      new_page_divs = client.dom_root.query_selector_all(
          '.browse[data-page-num]').length
      return true if new_page_divs != page_divs
    end
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
# @yield {Hash<Symbol, Object>} each search result
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
        client.clear_all
      end
    end

    break if done_scrolling
    done_scrolling = true unless dms_search_scroll(client)
  end
end

# NOTE: allow_popups is necessary to be able to click on the "search" link
client = WebkitRemote.local window: { width: 1024, height: 768 },
    port: ENV['PORT'], chrome_binary: ENV['CHROME']
dms_login client, 'leemoh@mit.edu', 'moresparkles'
dms_search client, 'Schools' => ARGV[0] do |result|
  File.write "#{result[:id]}.json", JSON.dump(result)
  pic_result = Net::HTTP.get URI.parse(result[:pic])
  File.binwrite "#{result[:id]}.jpg", pic_result
end
client.close_browser
