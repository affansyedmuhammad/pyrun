require "application_system_test_case"

class LayoutTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery staple"

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
