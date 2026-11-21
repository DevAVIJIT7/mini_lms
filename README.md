# Complete Build Journal: Mini-AMS + Mini-LMS (Rails OIDC Integration)

> **Build baseline:** Ruby `4.0.10`, Rails `8.1.4.1` (the versions used
> when the project was created on 2026-11-20). This is a historical
> build guide; do not interpret these as the latest versions available
> today.
>
> **Important completeness note:** This document combines the original
> OIDC integration blog with the app-creation steps recovered from the
> earlier conversation. The previous conversation's full
> domain-model/controller implementation was not available in the
> retrieved transcript. The OIDC code below is documented, but the exact
> earlier Mini-AMS business models, migrations, controllers, views and
> associations still need to be reconciled against the project source
> before this can be called a fully copy-and-run tutorial. Do not fill
> those gaps by guessing.

## 0. Start from two new Rails applications

The project has two separate Rails applications and two separate
PostgreSQL databases:

  ------------------------------------------------------------------------
  Application      Rails mode                  Local port Purpose
  ---------------- ---------------- --------------------- ----------------
  Mini-AMS         API-only                          4000 Member identity,
                                                          OAuth/OIDC
                                                          provider and AMS
                                                          API

  Mini-LMS         Full Rails                        3000 Browser UI, OIDC
                                                          client, local
                                                          user/session
  ------------------------------------------------------------------------

### 0.1 Check the Ruby and Rails versions

Run:

``` bash
ruby -v
rails -v
```

The build used Ruby `4.0.10` and Rails `8.1.4.1`. Install/select the
intended Ruby using your Ruby version manager first. Rails requires a
compatible Ruby version.

### 0.2 Install the Rails version used by this build

``` bash
gem install rails -v 8.1.4.1
```

Confirm:

``` bash
rails _8.1.4.1_ -v
```

Expected:

``` text
Rails 8.1.4.1
```

### 0.3 Generate Mini-AMS (API-only)

From the directory where you keep Rails projects:

``` bash
rails _8.1.4.1_ new mini_ams --api --database=postgresql
cd mini_ams
bin/rails db:create
bin/rails server -p 4000
```

Verify the app responds at `http://localhost:4000`.

**If Mini-AMS already exists, do not run `rails new` over it.** Continue
inside the existing project and preserve its models, migrations and
configuration.

### 0.4 Generate Mini-LMS (full Rails app)

In a separate terminal, return to your projects directory and run:

``` bash
rails _8.1.4.1_ new mini_lms --database=postgresql
cd mini_lms
bin/rails db:create
bin/rails server -p 3000
```

Mini-LMS is a regular Rails app---not API-only---because it needs views,
browser navigation and Rails sessions.

### 0.5 Verify both databases and servers

Run in each app:

``` bash
bin/rails db:prepare
bin/rails routes
```

Start each server in its own terminal:

``` bash
# Mini-AMS
bin/rails server -p 4000

# Mini-LMS
bin/rails server -p 3000
```

Use `http://` consistently for this local development setup. Do not send
HTTPS requests to Puma when it is listening for plain HTTP.

## 0.6 Project files that must be kept out of Git

Mini-AMS:

``` gitignore
/config/keys/*.pem
```

Mini-LMS:

``` gitignore
.env
.env.*
!.env.example
```

Never commit the OIDC private signing key, client secret, access token,
ID token, refresh token or authorization code.

## 0.7 Domain models and controllers: source reconciliation required

The project plan includes the following Mini-AMS business models:

-   `Member` (Devise-authenticated identity)
-   `Event`
-   `Registration`
-   `CreditType`
-   `Certification`
-   `CertificationActivity`

Mini-LMS includes the OIDC-linked `User` model and later sync/writeback
components.

The retrieved record confirms the names and responsibilities above, but
it does **not** contain the complete original migration files, exact
columns, validations, associations, callbacks, or full controller/view
source for every business model. Those must be copied from the actual
project repository to ensure the blog is reproducible. The OIDC/provider
and Mini-LMS login code documented in the following sections is the code
recovered from the working conversation.

------------------------------------------------------------------------

## 2. Architecture and responsibilities

### Mini-AMS

Mini-AMS owns the member identity and authentication process.

  ---------------------------------------------------------------------
  Component                          Responsibility
  ---------------------------------- ----------------------------------
  Devise                             Authenticates members using
                                     email/password and maintains the
                                     Mini-AMS browser session

  Doorkeeper                         OAuth 2.0 authorization server:
                                     registered clients, authorization
                                     codes, access tokens and scopes

  `doorkeeper-openid_connect`        Adds OIDC behavior: ID tokens,
                                     claims, UserInfo, discovery
                                     metadata and JWKS

  AMS API                            Exposes protected business data,
                                     such as member registrations and
                                     certification endpoints
  ---------------------------------------------------------------------

### Mini-LMS

Mini-LMS delegates login to Mini-AMS.

  ---------------------------------------------------------------------
  Component                          Responsibility
  ---------------------------------- ----------------------------------
  OmniAuth                           Middleware that starts
                                     authentication and handles the
                                     callback

  `omniauth_openid_connect`          OIDC client strategy:
                                     authorization redirect, token
                                     exchange, ID-token validation and
                                     user identity

  `omniauth-rails_csrf_protection`   CSRF protection for OmniAuth's
                                     POST request endpoint

  `Users` table                      Stores the local LMS user linked
                                     to the external OIDC subject

  Rails session                      Maintains the logged-in Mini-LMS
                                     user
  ---------------------------------------------------------------------

### Important distinction: OAuth 2.0 versus OIDC

OAuth 2.0 is primarily an authorization framework. It lets a client
obtain an access token to call a protected resource.

OpenID Connect builds an identity layer on top of OAuth 2.0. It
introduces the ID token and standard identity claims so the client can
verify who authenticated.

In this project:

-   **Devise** authenticates the human member in Mini-AMS.
-   **Doorkeeper** manages the OAuth authorization flow and access
    tokens.
-   **Doorkeeper OpenID Connect** issues OIDC identity information.
-   **OmniAuth OIDC** consumes that identity in Mini-LMS.

Doorkeeper is not a replacement for Devise. Devise answers "who has
signed in to Mini-AMS?" Doorkeeper answers "which registered client is
authorized, and what token/scopes does it receive?"

If Mini-LMS were a completely trusted internal application with no
delegated user login and no protected API boundary, OAuth might not be
strictly necessary. But for user SSO and scoped API access, the
OAuth/OIDC boundary is useful and safer than giving the LMS unrestricted
access.

## 3. Mini-AMS: prepare the member identity

Mini-AMS already existed as a Rails application. We retained it and
added the OAuth/OIDC provider functionality rather than generating a
second app.

The member table contains Devise authentication fields and application
identity fields. The relevant fields include:

``` ruby
email
encrypted_password
reset_password_token
reset_password_sent_at
remember_created_at
first_name
last_name
member_type
tenant_id
```

Devise's database fields are used for authentication. The profile fields
are available as OIDC claims later.

### Install the provider gems

Add the provider gems to Mini-AMS:

``` ruby
gem "devise"
gem "doorkeeper"
gem "doorkeeper-openid_connect"
```

Then install them:

``` bash
bundle install
```

If Devise is not already configured in the application, follow its
installation and model-generation steps. In this project, Devise was
already present and the member login page was working.

### Install Doorkeeper

Run the Doorkeeper installation generator if it has not already been
run:

``` bash
bin/rails generate doorkeeper:install
bin/rails db:migrate
```

The generator creates the Doorkeeper initializer and OAuth
application/token database tables. Keep the generated configuration and
then adjust it for the application.

### Configure Doorkeeper's resource owner authentication

Doorkeeper must know which signed-in member is authorizing the client.

In `config/initializers/doorkeeper.rb`, the resource owner authenticator
uses Devise's `current_member` helper:

``` ruby
resource_owner_authenticator do
  if current_member
    current_member
  else
    store_location_for(:member, request.url)
    redirect_to new_member_session_url
    nil
  end
end
```

There are two important details here:

1.  `current_member` returns the authenticated Devise member.
2.  When there is no signed-in member, save the original authorization
    URL before redirecting to the Devise login page.

The `store_location_for(:member, request.url)` line is important.
Without it, Devise may successfully authenticate the member and then
redirect to the Mini-AMS root page (`/`) instead of returning to the
pending `/oauth/authorize` request.

The explicit `nil` after `redirect_to` is also intentional. A Rails
`redirect_to` call returns a value; the authenticator should not
accidentally return that value as the resource owner.

### Configure the OIDC subject

An OIDC ID token needs a `sub` (subject) claim: a stable identifier for
the authenticated user within the issuer.

In `config/initializers/doorkeeper_openid_connect.rb`, configure the
subject using the member's ID:

``` ruby
subject do |resource_owner, _application|
  resource_owner.id.to_s
end
```

The subject is serialized as a string. Mini-LMS will store this value in
its local `users.uid` column.

**The Mini-AMS `members` table does not need a separate `uid` column for
this setup.** The OIDC subject is derived from the member's primary key.

### Configure the signing key

OIDC ID tokens are signed. For this project, an RSA private key was
generated locally:

``` bash
mkdir -p config/keys

openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out config/keys/oidc_private.pem

chmod 600 config/keys/oidc_private.pem
```

The OIDC initializer reads the private key:

``` ruby
signing_key File.read(
  Rails.root.join("config/keys/oidc_private.pem")
)
```

Do not commit the private key. Add this to Mini-AMS `.gitignore`:

``` gitignore
/config/keys/*.pem
```

Keep a secure backup of the key for environments that need to validate
tokens signed by this issuer. Replacing the key in a deployed
environment requires a deliberate key-rotation plan.

### Configure the issuer

The issuer must match the issuer advertised in discovery metadata and
the issuer expected by the OIDC client.

For local development:

``` ruby
issuer "http://localhost:4000"
```

The issuer is an identifier, not just a convenient URL. Keep it
consistent.

### Configure the access-token owner lookup

The OIDC UserInfo endpoint needs to resolve an access token back to its
member. The provider initializer can use:

``` ruby
resource_owner_from_access_token do |access_token|
  Member.find_by(id: access_token.resource_owner_id)
end
```

This is distinct from the resource-owner authenticator:

-   `resource_owner_authenticator` finds the signed-in member during
    authorization.
-   `resource_owner_from_access_token` finds the member represented by
    an already-issued access token.

### Optional identity claims

Once the basic flow works, add the identity claims that Mini-LMS needs.
For example:

``` ruby
claims do
  claim :email do |resource_owner|
    resource_owner.email
  end

  claim :given_name, scope: :profile do |resource_owner|
    resource_owner.first_name
  end

  claim :family_name, scope: :profile do |resource_owner|
    resource_owner.last_name
  end

  claim :member_type, scope: :profile do |resource_owner|
    resource_owner.member_type
  end
end
```

Only expose claims that the client needs. The standard OIDC names are
`given_name` and `family_name`; the client strategy's mapping into
`auth.info` should be inspected rather than assumed.

## 4. Register Mini-LMS as an OAuth/OIDC client

Doorkeeper needs a registered application representing Mini-LMS.

Create it in the Mini-AMS Rails console:

``` bash
bin/rails console
```

``` ruby
app = Doorkeeper::Application.create!(
  name: "Mini LMS",
  redirect_uri: "http://localhost:3000/auth/mini_ams/callback",
  scopes: "openid profile email",
  confidential: true
)
```

The important settings are:

-   `redirect_uri`: must exactly match the callback URL configured in
    Mini-LMS.
-   `scopes`: includes `openid`, which makes the request an OIDC
    request, plus `profile` and `email`.
-   `confidential: true`: this is a server-side web application that can
    keep a client secret.

The generated client ID and secret are credentials. Put them in
Mini-LMS's environment configuration. Never commit them or paste real
secrets into logs, tickets or chat.

## 5. Verify Mini-AMS discovery metadata

The OIDC discovery endpoint tells clients where the provider's endpoints
are and which capabilities it supports.

Open:

``` text
http://localhost:4000/.well-known/openid-configuration
```

Or run:

``` bash
curl http://localhost:4000/.well-known/openid-configuration
```

The working response included endpoint values similar to:

``` json
{
  "issuer": "http://localhost:4000",
  "authorization_endpoint": "http://localhost:4000/oauth/authorize",
  "token_endpoint": "http://localhost:4000/oauth/token",
  "revocation_endpoint": "http://localhost:4000/oauth/revoke",
  "introspection_endpoint": "http://localhost:4000/oauth/introspect",
  "userinfo_endpoint": "http://localhost:4000/oauth/userinfo",
  "jwks_uri": "http://localhost:4000/oauth/discovery/keys",
  "scopes_supported": ["openid", "profile", "email"],
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
```

The exact metadata depends on the configured gem versions and enabled
features. The key checks are:

-   `issuer` is exactly `http://localhost:4000`.
-   Authorization and token endpoints point to Mini-AMS.
-   `userinfo_endpoint` and `jwks_uri` are present.
-   `openid` is an advertised scope.
-   The signing algorithm matches the configured signing key.

The discovery endpoint was successfully tested before moving to
Mini-LMS.

## 6. Mini-LMS: create the relying-party application

Mini-LMS is a separate full Rails application using PostgreSQL. It runs
on port 3000.

The application was created as a regular Rails app rather than an
API-only app because it needs browser sessions, views and a login
experience.

### Add the OIDC client gems

Add these to the Mini-LMS `Gemfile`:

``` ruby
gem "omniauth"
gem "omniauth_openid_connect"
gem "omniauth-rails_csrf_protection"
```

For environment variables, add Dotenv in development and test if it is
not already available:

``` ruby
gem "dotenv-rails", groups: [:development, :test]
```

Install:

``` bash
bundle install
```

`omniauth-rails_csrf_protection` is important when using OmniAuth 2.x's
POST request phase. Do not disable CSRF protection just to make the
login button work.

### Configure environment variables

Create a `.env` file in the Mini-LMS project root:

``` dotenv
MINI_AMS_CLIENT_ID=your_client_id
MINI_AMS_CLIENT_SECRET=your_client_secret
```

Use the actual values from the registered Doorkeeper application, but do
not commit this file.

Add to `.gitignore`:

``` gitignore
.env
.env.*
!.env.example
```

Verify that the application can read the variable names without printing
the secret:

``` bash
bin/rails runner 'puts ENV["MINI_AMS_CLIENT_ID"].present?'
```

Expected output:

``` text
true
```

You can commit a `.env.example` containing placeholder values, but never
real credentials.

## 7. Configure OmniAuth OIDC in Mini-LMS

Create or update:

``` text
config/initializers/omniauth.rb
```

The working configuration used explicit endpoints and disabled discovery
while troubleshooting the local HTTP discovery/TLS issue:

``` ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :openid_connect,
    name: :mini_ams,
    issuer: "http://localhost:4000",
    discovery: false,
    scope: %i[openid profile email],
    response_type: :code,
    uid_field: "sub",
    client_options: {
      identifier: ENV.fetch("MINI_AMS_CLIENT_ID"),
      secret: ENV.fetch("MINI_AMS_CLIENT_SECRET"),
      redirect_uri: "http://localhost:3000/auth/mini_ams/callback",
      authorization_endpoint: "http://localhost:4000/oauth/authorize",
      token_endpoint: "http://localhost:4000/oauth/token",
      userinfo_endpoint: "http://localhost:4000/oauth/userinfo",
      jwks_uri: "http://localhost:4000/oauth/discovery/keys"
    }
  )
end
```

Why `discovery: false` here?

Initially, the OIDC strategy attempted an SSL connection to the local
Puma server even though Mini-AMS was serving plain HTTP. That produced
an error similar to:

``` text
SSL_connect ... wrong version number
OpenIDConnect::Discovery::DiscoveryFailed
```

The local discovery document itself was reachable over HTTP. To isolate
the problem, the client was configured with explicit endpoint URLs and
`discovery: false`. The request then progressed to the authorization
endpoint.

This is a troubleshooting configuration, not a general recommendation to
disable discovery. Once the integration is stable, discovery can be
revisited. If enabled, make sure the discovery URL and issuer are being
interpreted with the correct HTTP scheme by the exact installed gem
versions.

Keep all local endpoint URLs consistently `http://` while using plain
HTTP Puma. A browser or client attempting HTTPS against an HTTP Puma
listener can produce:

``` text
Puma::HttpParserError:
Invalid HTTP format, parsing fails.
Are you trying to open an SSL connection to a non-SSL Puma?
```

## 8. Configure Mini-LMS routes and callback controller

OmniAuth middleware handles the request path `/auth/mini_ams`. Rails
needs a callback route to receive the result.

In `config/routes.rb`:

``` ruby
Rails.application.routes.draw do
  root "sessions#new"

  get "/auth/mini_ams/callback", to: "sessions#mini_ams"
  get "/auth/failure", to: "sessions#failure"

  post "/logout", to: "sessions#destroy"
end
```

Generate the controller:

``` bash
bin/rails generate controller Sessions new
```

A first working callback implementation is:

``` ruby
class SessionsController < ApplicationController
  def new
  end

  def mini_ams
    auth = request.env["omniauth.auth"]

    user = User.find_or_initialize_by(
      provider: "mini_ams",
      uid: auth.uid
    )

    user.email = auth.info.email
    user.first_name = auth.info.first_name
    user.last_name = auth.info.last_name
    user.save!

    session[:user_id] = user.id

    redirect_to root_path, notice: "Successfully logged in!"
  end

  def failure
    redirect_to root_path, alert: params[:message]
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out successfully."
  end
end
```

This is the initial learning-project implementation. Before production
use, add defensive handling for a missing or malformed auth hash,
missing claims, failed persistence and callback errors. Do not log raw
token values.

Also inspect the actual `auth.info` structure during development using
safe, non-secret fields. Depending on the strategy and claim mapping,
given/family names may not appear under the exact `first_name` and
`last_name` keys shown above. Do not log the entire auth hash because it
may contain access, ID and refresh tokens.

## 9. Create the local Mini-LMS user table

The local user stores the identity link to Mini-AMS.

The model was generated with:

``` bash
bin/rails generate model User \
  uid:string email:string first_name:string last_name:string provider:string
```

The migration includes:

``` ruby
add_index :users, [:provider, :uid], unique: true
add_index :users, :email
```

Then run:

``` bash
bin/rails db:migrate
```

The unique composite index ensures that a given provider subject maps to
only one local user.

### What is `uid`?

The OIDC `sub` claim is the stable subject identifier from the identity
provider.

Mini-LMS configures:

``` ruby
uid_field: "sub"
```

Therefore:

``` ruby
auth.uid
```

is the OIDC subject, and it is stored in:

``` ruby
users.uid
```

This is why Mini-AMS does not need a separate `uid` column. Mini-AMS can
use `members.id.to_s` as the OIDC subject, while Mini-LMS stores that
value locally.

## 10. Add the current-user helper

In Mini-LMS `app/controllers/application_controller.rb`:

``` ruby
class ApplicationController < ActionController::Base
  helper_method :current_user

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
```

This is the initial session lookup. For production, protect
authenticated pages with a `before_action`, handle expired/deleted
users, and regenerate the session at login to reduce session-fixation
risk.

## 11. Build the Mini-LMS login page

In `app/views/sessions/new.html.erb`:

``` erb
<h1>Mini LMS</h1>

<% if session[:user_id].present? %>
  <p>You are logged in.</p>

  <%= button_to "Logout", logout_path, method: :post %>
<% else %>
  <p>Welcome! Please sign in.</p>

  <%= button_to "Login with Mini-AMS",
                "/auth/mini_ams",
                method: :post,
                data: { turbo: false } %>
<% end %>
```

The `data: { turbo: false }` setting is essential in this Rails/Turbo
setup.

### Why disable Turbo on the login button?

The first attempt used a normal form submission, but Turbo intercepted
the form and submitted it with `fetch()`.

The browser then tried to follow the cross-origin redirect to:

``` text
http://localhost:4000/oauth/authorize
```

as a fetch request. That caused a CORS preflight:

``` text
Access to fetch ... has been blocked by CORS policy
No 'Access-Control-Allow-Origin' header is present
```

The browser also sent an `OPTIONS` request to Mini-AMS, where Doorkeeper
had no matching OPTIONS route.

The problem was not that the OAuth authorization endpoint needed CORS.
The problem was that the authorization flow was being initiated as an
AJAX request.

Disabling Turbo on this one form makes it a normal top-level browser
form submission. The browser follows the redirect as a navigation, which
is the expected OIDC authorization flow.

### Why keep POST and CSRF protection?

OmniAuth 2.x allows POST as its default request method. A GET request to
`/auth/mini_ams` generated a security warning because GET-based
authentication initiation can be vulnerable to login CSRF.

The final setup keeps POST and `omniauth-rails_csrf_protection`. Do not
add this insecure workaround:

``` ruby
OmniAuth.config.allowed_request_methods = [:get, :post]
```

The final login button uses POST, with Turbo disabled.

## 12. End-to-end login flow

Once both applications are running, the intended flow is:

``` text
Browser
  |
  | 1. Click Login with Mini-AMS
  |    POST http://localhost:3000/auth/mini_ams
  |    Rails authenticity token included
  v
Mini-LMS OmniAuth middleware
  |
  | 2. Build OIDC authorization request
  |    client_id
  |    redirect_uri
  |    response_type=code
  |    scope=openid profile email
  |    state
  |    nonce
  v
Browser navigation / redirect
  |
  | 3. GET http://localhost:4000/oauth/authorize
  v
Mini-AMS Doorkeeper
  |
  | 4. No signed-in member?
  v
Devise login page
  |
  | 5. POST /members/sign_in
  v
Devise authenticates Member
  |
  | 6. Resume original authorization URL
  v
Mini-AMS Doorkeeper authorization
  |
  | 7. Consent/authorization
  v
Mini-AMS issues authorization code
  |
  | 8. Redirect to registered callback
  v
Mini-LMS /auth/mini_ams/callback
  |
  | 9. Exchange authorization code for tokens
  |    Validate ID token
  |    Obtain identity claims
  v
Mini-LMS SessionsController
  |
  | 10. Find/create local User
  |     Store local user ID in session
  v
Mini-LMS homepage: logged in
```
<img width="3152" height="2286" alt="mermaid-diagram" src="https://github.com/user-attachments/assets/96c13a29-8ae1-4471-b10e-66b53899e7ae" />

## 13. Debugging issues encountered and their fixes

This section records the actual problems encountered during the build,
why they happened and what fixed them.

### Issue A: OIDC discovery tried HTTPS against local HTTP Puma

**Symptom**

``` text
SSL_connect ... wrong version number
OpenIDConnect::Discovery::DiscoveryFailed
```

**Cause**

The OIDC client attempted an SSL/TLS connection to a Puma server
listening for plain HTTP.

**Resolution used during local troubleshooting**

Set `discovery: false` and provide explicit HTTP endpoint URLs in the
OmniAuth client configuration:

``` ruby
discovery: false,
client_options: {
  authorization_endpoint: "http://localhost:4000/oauth/authorize",
  token_endpoint: "http://localhost:4000/oauth/token",
  userinfo_endpoint: "http://localhost:4000/oauth/userinfo",
  jwks_uri: "http://localhost:4000/oauth/discovery/keys"
}
```

Keep issuer and endpoint URLs consistent. Revisit discovery after the
flow is stable.

### Issue B: OPTIONS request had no Doorkeeper route

**Symptom**

``` text
Started OPTIONS "/oauth/authorize..."
ActionController::RoutingError:
No route matches [OPTIONS] "/oauth/authorize"
```

**Cause**

The authorization flow was being treated as a cross-origin fetch/AJAX
request. The browser sent a CORS preflight.

**Resolution**

Use a regular form POST to `/auth/mini_ams` and disable Turbo on that
form:

``` erb
<%= button_to "Login with Mini-AMS",
              "/auth/mini_ams",
              method: :post,
              data: { turbo: false } %>
```

Do not add an OPTIONS route to Doorkeeper to work around this. A normal
top-level browser navigation does not need CORS for the authorization
redirect.

### Issue C: GET request to OmniAuth was rejected

**Symptom**

``` text
No route matches [GET] "/auth/mini_ams"
```

**Cause**

OmniAuth 2.x defaults to POST-only request initiation.

**Temporary experiment**

GET was allowed temporarily:

``` ruby
OmniAuth.config.allowed_request_methods = [:get, :post]
```

OmniAuth printed a warning about CSRF risk. This was not retained.

**Final resolution**

Return to POST-only and use the CSRF-protected form. Disable Turbo only
for this form.

### Issue D: Devise login succeeded but redirected to Mini-AMS root

**Symptom**

Mini-AMS logs showed:

``` text
Redirected to http://localhost:4000/
```

The user was authenticated, but Doorkeeper's pending `/oauth/authorize`
request was not resumed.

**Cause**

The original authorization URL had not been stored as the Devise return
location for the `:member` scope.

**Final resolution**

Use Devise's `store_location_for` with the correct scope in Doorkeeper's
resource owner authenticator:

``` ruby
resource_owner_authenticator do
  if current_member
    current_member
  else
    store_location_for(:member, request.url)
    redirect_to new_member_session_url
    nil
  end
end
```

The scope matters: this app uses `:member`, not `:user`.

After this change, the authorization request resumed after Devise login.
The user confirmed that this worked.

### Issue E: ID token nonce mismatch

**Symptom**

``` text
OpenIDConnect::ResponseObject::IdToken::InvalidNonce
Invalid ID Token: Nonce does not match
```

**What nonce does**

The client generates a random nonce and sends it in the authorization
request. The provider must include that same nonce in the ID token. The
client compares the returned nonce with the original one to mitigate
replay attacks.

The Mini-AMS authorization request log showed a nonce parameter:

``` text
Parameters: {
  "client_id" => "...",
  "nonce" => "...",
  "redirect_uri" => "...",
  "response_type" => "code",
  "scope" => "openid profile email",
  "state" => "..."
}
```

A previous troubleshooting hypothesis was that the Doorkeeper consent
form might not preserve the nonce when submitting the authorization
decision. That has **not yet been confirmed**.

Do not assume that adding a hidden field is definitely the fix. First
inspect the actual ID token's nonce claim safely and compare it with the
nonce sent in the authorization request. Never paste or log the raw ID
token.

The nonce problem remains a verification item until a fresh complete
login succeeds.

## 14. Safe diagnostics: inspect tokens without leaking them

Tokens are credentials. Do not print them in full in Rails logs,
terminal output, screenshots or chat.

When debugging the callback, inspect only safe metadata, such as:

-   Whether an auth hash exists.
-   The provider name.
-   Whether `uid` is present.
-   Which claim keys are present.
-   Whether an access token exists.
-   Whether an ID token exists.
-   Whether a refresh token exists.
-   Whether token validation succeeded.

For example, during local debugging, inspect only the non-secret keys:

``` ruby
auth = request.env["omniauth.auth"]

Rails.logger.info(
  "OIDC callback present=#{auth.present?}, " \
  "provider=#{auth&.provider.inspect}, " \
  "uid_present=#{auth&.uid.present?}, " \
  "info_keys=#{auth&.info&.keys}"
)
```

Avoid:

``` ruby
Rails.logger.info(auth.to_h)
```

The complete hash may contain access tokens, ID tokens and refresh
tokens.

If you need to inspect a JWT during debugging, decode it locally without
sharing the raw token. Remember that decoding a JWT is not the same as
validating its signature. The OIDC client must perform signature,
issuer, audience, expiry, state and nonce validation.

## 15. Current progress

### Completed

-   [x] Mini-AMS Rails application and Devise member authentication.
-   [x] Doorkeeper installed and configured.
-   [x] OIDC extension installed and configured.
-   [x] RSA signing key generated and excluded from Git.
-   [x] OIDC issuer configured as `http://localhost:4000`.
-   [x] OIDC subject configured from `Member#id`.
-   [x] UserInfo access-token owner lookup configured.
-   [x] Mini-LMS registered as a confidential Doorkeeper application.
-   [x] Mini-AMS discovery metadata endpoint verified.
-   [x] Mini-LMS Rails application created.
-   [x] Mini-LMS user table created with unique `(provider, uid)` index.
-   [x] OmniAuth OIDC client configured.
-   [x] Environment variables configured for client credentials.
-   [x] Mini-LMS callback route and SessionsController added.
-   [x] Mini-LMS login/logout view added.
-   [x] Turbo disabled for the external login form to avoid fetch/CORS
    behavior.
-   [x] OmniAuth POST request and CSRF protection retained.
-   [x] Devise return location fixed using
    `store_location_for(:member, request.url)`.
-   [x] User confirmed the login flow worked after the return-location
    fix.

### Still to verify or build

-   [ ] Confirm a fresh OIDC login completes without `InvalidNonce`.
-   [ ] Verify the ID token's nonce matches the authorization request,
    without logging the token.
-   [ ] Verify the expected claims (`sub`, `email`, `given_name`,
    `family_name`) arrive in Mini-LMS.
-   [ ] Harden callback error handling and session management.
-   [ ] Add automated tests for OIDC callback and failure cases.
-   [ ] Implement registration synchronization from Mini-AMS to
    Mini-LMS.
-   [ ] Implement safe revocation of integration-owned orders.
-   [ ] Implement certification/activity writeback.
-   [ ] Add audit logging and job tests.

## 16. Planned next milestones

After the OIDC login is fully verified, continue in small, testable
milestones.

### Milestone 1: Finish identity verification

Verify the callback receives the correct subject and claims. Confirm
issuer, audience, expiry, signature, state and nonce validation. Do not
weaken token validation to make the login pass.

### Milestone 2: Registration synchronization

Mini-LMS will call the protected Mini-AMS registrations endpoint:

``` text
GET /api/v1/members/:member_id/registrations
```

The API request should use the access token and the required tenant
context (`x-tenant`) according to the AMS API contract.

The sync should grant access for active registered events. If the
registrations API fails, do not revoke existing access.

### Milestone 3: Safe order revocation

Only revoke orders created by this integration. The planned ownership
criteria are:

``` text
manual = false
description = "integration"
```

Never revoke manually created orders or orders owned by another process.

### Milestone 4: Certification and activity writeback

Mini-LMS will post certification data and activities to Mini-AMS.
Unmapped credit types should be skipped with a warning. Treat the
writeback as successful only if at least one activity is successfully
posted, according to the agreed business rule.

### Milestone 5: Jobs, audit logs and tests

Add background jobs, audit records and tests for success, API failure,
missing mappings, duplicate events and safe revocation. The planned
sync/writeback jobs should not blindly retry non-idempotent writes;
design idempotency and failure handling deliberately.

## 17. Security checklist

Before using this design beyond local development:

-   Use HTTPS for both applications.
-   Keep client secrets and private signing keys out of source control.
-   Use exact redirect URI allowlists.
-   Keep OmniAuth POST-only and retain CSRF protection.
-   Keep Turbo disabled only for the external OIDC login form, not
    globally.
-   Validate ID-token signature, issuer, audience, expiry, state and
    nonce.
-   Do not bypass nonce validation to make login succeed.
-   Do not log access tokens, refresh tokens, ID tokens, authorization
    codes or client secrets.
-   Use least-privilege scopes.
-   Protect API endpoints with access-token authentication and tenant
    authorization.
-   Rotate credentials and signing keys through a planned process.
-   Add session fixation protection and robust logout/session-expiry
    behavior.
-   Ensure registration sync failures cannot accidentally revoke valid
    access.

## Conclusion

The core SSO path is now in place: Mini-LMS initiates an OIDC login,
Mini-AMS authenticates the member through Devise, Doorkeeper resumes the
original authorization request, and Mini-LMS receives the OIDC callback.

The most instructive debugging lessons were:

1.  OIDC authorization should be a browser navigation, not a
    cross-origin Turbo/fetch request.
2.  OmniAuth 2.x should use POST with CSRF protection rather than
    enabling GET casually.
3.  Devise must preserve the original authorization URL using the
    correct scope (`:member`) so Doorkeeper can resume authorization.
4.  OAuth 2.0 access tokens and OIDC ID tokens serve different purposes.
5.  Nonce validation is a security check; investigate mismatches rather
    than disabling the check.

The next task is to verify the nonce and claims on a fresh login, then
proceed to registration synchronization.

## Appendix A. Source files needed to finish the copy-and-run edition

To make every step exact and runnable for another developer, reconcile
and include the actual contents of these files from the two
repositories:

### Mini-AMS

-   `Gemfile` and `Gemfile.lock` (Ruby/Rails and gem versions)
-   `config/application.rb`, `config/routes.rb`
-   `config/initializers/devise.rb`
-   `config/initializers/doorkeeper.rb`
-   `config/initializers/doorkeeper_openid_connect.rb`
-   `app/models/member.rb`
-   all event/registration/credit/certification model files
-   all migrations, including Doorkeeper and domain migrations
-   all API controllers, authentication concerns and serializers
-   relevant views/templates, including Doorkeeper authorization/consent
    templates if customized
-   request specs or other tests that demonstrate the endpoints

### Mini-LMS

-   `Gemfile` and `Gemfile.lock`
-   `config/routes.rb` and `config/initializers/omniauth.rb`
-   `app/models/user.rb` and its migration
-   `app/controllers/application_controller.rb`
-   `app/controllers/sessions_controller.rb`
-   `app/views/sessions/new.html.erb`
-   `.env.example` with placeholder values only
-   tests for the callback, failed login, and session handling

### Validation checklist for the final tutorial

-   [ ] Run the instructions from clean folders on a supported Ruby
    installation.
-   [ ] Run `bundle install` in both applications.
-   [ ] Run `bin/rails db:prepare` in both applications.
-   [ ] Verify routes and generated migrations.
-   [ ] Complete a fresh OIDC login and confirm `sub`, issuer, audience,
    expiry, state and nonce validation.
-   [ ] Confirm Mini-LMS creates/updates the correct local user.
-   [ ] Confirm no secrets are present in source or logs.
-   [ ] Add the exact business API models/controllers and test their
    requests.
-   [ ] Add the integration jobs only after the API contracts and
    idempotency rules are verified.

**Next required input to finish the full version:** upload a ZIP of the
Mini-AMS and Mini-LMS source folders (exclude `.env`, private keys,
credentials, `tmp`, `log`, and `node_modules`). I can then replace the
source-reconciliation notes with the exact models, migrations,
controllers, routes, views and tests, and verify that the command
sequence matches the code.
