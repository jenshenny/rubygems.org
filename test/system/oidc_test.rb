require "application_system_test_case"

class OIDCTest < ApplicationSystemTestCase
  setup do
    @user = create(:user, password: PasswordHelpers::SECURE_TEST_PASSWORD)
    @provider = create(:oidc_provider, issuer: "https://token.actions.githubusercontent.com")
    @api_key_role = create(:oidc_api_key_role, user: @user, provider: @provider)
    @id_token = create(:oidc_id_token, user: @user, api_key_role: @api_key_role)
  end

  def sign_in
    visit sign_in_path
    fill_in "Email or Username", with: @user.reload.email
    fill_in "Password", with: @user.password
    click_button "Sign in"
  end

  def verify_session # rubocop:disable Minitest/TestMethodName
    page.assert_title(/^Confirm Password/)
    fill_in "Password", with: @user.password
    click_button "Confirm"
  end

  test "viewing providers" do
    sign_in
    visit profile_oidc_providers_path
    verify_session

    page.assert_selector "h1", text: "OIDC Providers"
    page.assert_text(/displaying 1 provider/i)
    page.click_link "https://token.actions.githubusercontent.com"

    page.assert_selector "h1", text: "OIDC Provider"
    page.assert_text "https://token.actions.githubusercontent.com"
    page.assert_text "https://token.actions.githubusercontent.com/.well-known/jwks"
    page.assert_text(/Displaying 1 api key role/i)
    assert_link @id_token.api_key_role.name, href: profile_oidc_api_key_role_path(@id_token.api_key_role.token)
  end

  test "viewing api key roles" do
    sign_in
    visit profile_oidc_api_key_roles_path
    verify_session

    page.assert_selector "h1", text: "OIDC API Key Roles"
    page.assert_text(/displaying 1 api key role/i)
    page.click_link @id_token.api_key_role.name

    page.assert_selector "h1", text: "API Key Role #{@id_token.api_key_role.name}"
    page.assert_text @id_token.api_key_role.token
    page.assert_text "Scopes\npush_rubygem"
    page.assert_text "Gems\nAll Gems"
    page.assert_text "Valid for\n30 minutes"
    page.assert_text "Effect\nallow"
    page.assert_text "Principal\nhttps://token.actions.githubusercontent.com"
    page.assert_text "Conditions\nsub string_equals repo:segiddins/oidc-test:ref:refs/heads/main"
    page.assert_text(/Displaying 1 id token/i)
    assert_link "View provider https://token.actions.githubusercontent.com", href: profile_oidc_provider_path(@provider)
    assert_link @id_token.jti, href: profile_oidc_id_token_path(@id_token)
  end

  test "viewing id tokens" do
    sign_in
    visit profile_oidc_id_tokens_path
    verify_session

    page.assert_selector "h1", text: "OIDC ID Tokens"
    page.assert_text(/displaying 1 id token/i)
    page.click_link @id_token.jti

    page.assert_selector "h1", text: "OIDC ID Token"
    page.assert_text "CREATED AT\n#{@id_token.created_at.to_fs(:long)}"
    page.assert_text "EXPIRES AT\n#{@id_token.api_key.expires_at.to_fs(:long)}"
    page.assert_text "JWT ID\n#{@id_token.jti}"
    assert_link @api_key_role.name, href: profile_oidc_api_key_role_path(@api_key_role.token)
    assert_link "https://token.actions.githubusercontent.com", href: profile_oidc_provider_path(@provider)
    page.assert_text "jti\n#{@id_token.jti}"
    page.assert_text "claim1\nvalue1"
    page.assert_text "claim2\nvalue2"
    page.assert_text "typ\nJWT"
  end

  test "creating an api key role" do
    rubygem = create(:rubygem, owners: [@user])
    create(:version, rubygem: rubygem, metadata: { "source_code_uri" => "https://github.com/example/repo" })

    sign_in
    visit rubygem_path(rubygem.slug)
    click_link "OIDC: Create"
    verify_session

    page.assert_selector "h1", text: "New OIDC API Key Role"
    assert_field "Name", with: "Push #{rubygem.name}"
    assert_select "OIDC provider", options: ["https://token.actions.githubusercontent.com"], selected: "https://token.actions.githubusercontent.com"
    assert_checked_field "Push rubygem"
    assert_field "Valid for", with: "PT30M"
    assert_select "Gem Scope", options: ["All Gems", rubygem.name], selected: rubygem.name

    assert_select "Effect", options: %w[allow deny], selected: "allow",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_effect"
    assert_field "Claim", with: "aud",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_0_claim"
    assert_select "Operator", options: ["String Equals", "String Matches"], selected: "String Equals",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_0_operator"
    assert_field "Value", with: Gemcutter::HOST,
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_0_value"
    assert_field "Claim", with: "repository",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_1_claim"
    assert_select "Operator", options: ["String Equals", "String Matches"], selected: "String Equals",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_1_operator"
    assert_field "Value", with: "example/repo",
      id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_1_value"

    page.scroll_to page.find(id: "oidc_api_key_role_access_policy_statements_attributes_0_conditions_attributes_1_claim")

    click_button "Create Api key role"

    page.assert_selector "h1", text: "API Key Role Push #{rubygem.name}"

    role = OIDC::ApiKeyRole.where(name: "Push #{rubygem.name}", user: @user, provider: @provider).sole

    token = role.token
    expected = {
      "name" => "Push #{rubygem.name}",
      "token" => token,
      "api_key_permissions" => {
        "scopes" => ["push_rubygem"],
        "valid_for" => 1800,
        "gems" => [rubygem.name]
      },
      "access_policy" => {
        "statements" => [
          {
            "effect" => "allow",
            "principal" => { "oidc" => "https://token.actions.githubusercontent.com" },
            "conditions" => [
              { "operator" => "string_equals", "claim" => "aud", "value" => "localhost" },
              { "operator" => "string_equals", "claim" => "repository", "value" => "example/repo" }
            ]
          }
        ]
      }
    }

    assert_equal(expected, role.as_json.slice(*expected.keys))

    click_button "Edit API Key Role"
    page.scroll_to :bottom
    click_button "Update Api key role"

    page.assert_selector "h1", text: "API Key Role Push #{rubygem.name}"
    assert_equal(expected, role.reload.as_json.slice(*expected.keys))

    click_button "Edit API Key Role"

    click_button "Add statement"

    statements = page.find_all(id: /oidc_api_key_role_access_policy_statements_attributes_\d+_wrapper/)

    assert_equal 2, statements.size

    new_statement = statements.last
    new_statement.select "deny", from: "Effect"
    new_statement.fill_in "Claim", with: "sub"
    new_statement.select "String Matches", from: "Operator"
    new_statement.fill_in "Value", with: "repo:example/repo:ref:refs/tags/.*"
    new_statement.click_button "Add condition"
    new_condition = new_statement.find_all(id: /oidc_api_key_role_access_policy_statements_attributes_\d+_conditions_attributes_\d+_wrapper/).last
    new_condition.fill_in "Claim", with: "fudge"
    new_condition.select "String Equals", from: "Operator"

    statements.first.find_all("button", text: "Remove condition").last.click

    page.assert_selector("button.form__remove_nested_button", text: "Remove condition", count: 3)

    click_button "Update Api key role"

    page.assert_text "Access policy statements[1] conditions[1] claim unknown for the provider"
    assert_equal(expected, role.reload.as_json.slice(*expected.keys))

    page.find_field("Claim", with: "fudge").fill_in with: "event_name"

    page.find_field("Name").fill_in with: "Push gems"
    page.select "All Gems", from: "Gem Scope"
    page.unselect rubygem.name, from: "Gem Scope"
    page.check "Yank rubygem"

    click_button "Update Api key role"

    page.assert_selector "h1", text: "API Key Role Push gems"
    assert_equal(expected.merge(
                   "name" => "Push gems",
                   "api_key_permissions" => {
                     "scopes" => %w[push_rubygem yank_rubygem], "valid_for" => 1800, "gems" => nil
                   },
                   "access_policy" => {
                     "statements" => [
                       {
                         "effect" => "allow",
                         "principal" => { "oidc" => "https://token.actions.githubusercontent.com" },
                         "conditions" => [
                           { "operator" => "string_equals", "claim" => "aud", "value" => "localhost" }
                         ]
                       },
                       {
                         "effect" => "allow",
                         "principal" => { "oidc" => "https://token.actions.githubusercontent.com" },
                         "conditions" => [
                           { "operator" => "string_matches", "claim" => "sub", "value" => "repo:example/repo:ref:refs/tags/.*" },
                           { "operator" => "string_equals", "claim" => "event_name", "value" => "" }
                         ]
                       }
                     ]
                   }
                 ), role.reload.as_json.slice(*expected.keys))
  end
end
