require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

  test "a long address in the sidebar wraps instead of being cut off" do
    long = users(:google_only)
    long.update!(email_address: "a.rather.long.first.name@windbornesystems.com", password: "Correct-Horse-Battery-9", password_confirmation: "Correct-Horse-Battery-9")
    page.current_window.resize_to(1600, 900)
    visit login_path
    fill_in "Email", with: long.email_address
    fill_in "Password", with: "Correct-Horse-Battery-9"
    click_button "Sign in"
    assert_selector "h1", text: "Runs"

    assert_selector ".sidebar-identity", text: "a.rather.long.first.name@windbornesystems.com"
    overflow = page.evaluate_script("(el => el.scrollWidth > el.clientWidth + 1)(document.querySelector('.sidebar-identity'))")
    assert_not overflow, "the address must wrap after the @, never overflow or clip"

    # A typical company address fits on one line.
    click_button "Sign out"
    fill_in "Email", with: users(:verified).email_address
    fill_in "Password", with: PASSWORD
    click_button "Sign in"
    assert_selector "h1", text: "Runs"
    lines = page.evaluate_script("(el => Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight)))(document.querySelector('.sidebar-identity'))")
    assert_equal 1, lines, "verified@windbornesystems.com should fit on one line"
  end

  test "on a wide screen the sidebar sits left and the page fills the rest; on a phone it stacks" do
    page.current_window.resize_to(1600, 900)
    visit login_path
    fill_in "Email", with: users(:verified).email_address
    fill_in "Password", with: PASSWORD
    click_button "Sign in"
    assert_selector "h1", text: "Runs"

    aside = rect("aside")
    main = rect("main")
    content = rect(".page")
    assert_includes 180..320, aside[:width]
    assert_operator main[:left], :>=, aside[:right] - 1, "main must start to the right of the sidebar"
    assert_operator content[:width], :>, 1150, "the page must use the width available, not stop at a fixed limit"

    page.current_window.resize_to(390, 844)
    assert_selector "aside"
    aside = rect("aside")
    main = rect("main")
    assert_operator main[:top], :>=, aside[:bottom] - 1, "on a phone the navigation stacks above the content"
    assert_operator aside[:height], :<, 200, "the stacked navigation must stay compact"
    assert_selector "aside nav a", text: "Runs"
  end

  private
    def rect(selector)
      r = page.evaluate_script("(r => ({left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height}))(document.querySelector(#{selector.to_json}).getBoundingClientRect())")
      r.transform_keys(&:to_sym)
    end
end
