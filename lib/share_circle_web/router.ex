defmodule ShareCircleWeb.Router do
  use ShareCircleWeb, :router

  import ShareCircleWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ShareCircleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :accepts_json do
    plug :accepts, ["html", "json"]
  end

  pipeline :api_public do
    plug :accepts, ["json"]
    plug ShareCircleWeb.Plugs.RateLimit, bucket: :auth
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug ShareCircleWeb.Plugs.AuthenticateApi
    plug ShareCircleWeb.Plugs.RateLimit, bucket: :read
  end

  pipeline :api_write do
    plug ShareCircleWeb.Plugs.RateLimit, bucket: :write
  end

  pipeline :api_family do
    plug ShareCircleWeb.Plugs.LoadCurrentFamily
  end

  scope "/", ShareCircleWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/setup", SetupLive, :index
  end

  # OpenAPI spec and Swagger UI — no auth required
  scope "/api/v1" do
    pipe_through [:accepts_json]

    get "/openapi.json", OpenApiSpex.Plug.RenderSpec, []
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/v1/openapi.json"
  end

  # Public auth endpoints (no token required)
  scope "/api/v1/auth", ShareCircleWeb.Api.V1 do
    pipe_through :api_public

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/password/reset/request", AuthController, :request_password_reset
    post "/password/reset/confirm", AuthController, :confirm_password_reset
    post "/email/confirm", AuthController, :confirm_email
  end

  scope "/api/v1", ShareCircleWeb.Api.V1 do
    pipe_through :api

    # Authenticated auth management
    post "/auth/logout", AuthController, :logout
    post "/auth/refresh", AuthController, :refresh
    post "/auth/email/resend", AuthController, :resend_confirmation
    get "/auth/sessions", AuthController, :list_sessions
    delete "/auth/sessions/:id", AuthController, :delete_session

    # Current user
    get "/me", MeController, :show
    patch "/me", MeController, :update
    delete "/me", MeController, :delete
    get "/me/families", MeController, :families

    # Create family (no family context yet)
    post "/families", FamilyController, :create

    # Accept invitation (authenticated, not family-scoped)
    post "/invitations/:token/accept", InvitationController, :accept

    # Media download (access-controlled redirect to presigned URL)
    get "/media/:id/download", MediaController, :download

    # Complete upload (not family-scoped; session carries family context)
    post "/uploads/:upload_id/complete", UploadController, :complete_upload

    # Single-resource post/comment routes (membership checked in context)
    resources "/posts", PostController, only: [:show, :update, :delete] do
      resources "/comments", CommentController, only: [:index]
      put "/reactions/:emoji", ReactionController, :upsert
      delete "/reactions/:emoji", ReactionController, :delete
    end

    resources "/comments", CommentController, only: [:update, :delete] do
      put "/reactions/:emoji", ReactionController, :upsert
      delete "/reactions/:emoji", ReactionController, :delete
    end

    # Notifications
    get "/notifications", NotificationController, :index
    post "/notifications/read-all", NotificationController, :read_all
    post "/notifications/:id/read", NotificationController, :read

    # Notification preferences
    get "/me/notification-preferences", NotificationPreferenceController, :index
    patch "/me/notification-preferences/:kind", NotificationPreferenceController, :update

    # Push subscriptions
    post "/me/push-subscriptions", PushSubscriptionController, :create
    delete "/me/push-subscriptions/:id", PushSubscriptionController, :delete

    # Event routes (membership checked in context)
    get "/events/:id", EventController, :show
    patch "/events/:id", EventController, :update
    delete "/events/:id", EventController, :delete
    get "/events/:event_id/rsvp", RsvpController, :show
    put "/events/:event_id/rsvp", RsvpController, :upsert

    # Conversation + message routes (membership checked in context)
    get "/conversations/:id", ConversationController, :show
    get "/conversations/:conversation_id/messages", MessageController, :index
    post "/conversations/:conversation_id/messages", MessageController, :create
    patch "/messages/:id", MessageController, :update
    delete "/messages/:id", MessageController, :delete
    post "/conversations/:conversation_id/read", MessageController, :mark_read

    # Family-scoped routes (LoadCurrentFamily required)
    scope "/families/:family_id" do
      pipe_through :api_family

      get "/", FamilyController, :show
      get "/members", MemberController, :index
      get "/invitations", InvitationController, :index
      get "/conversations", ConversationController, :index
      get "/events", EventController, :index

      scope "/" do
        pipe_through :api_write

        patch "/", FamilyController, :update
        delete "/", FamilyController, :delete
        delete "/members/:user_id", MemberController, :delete
        patch "/members/:user_id", MemberController, :update
        post "/invitations", InvitationController, :create
        delete "/invitations/:id", InvitationController, :delete

        resources "/posts", PostController, only: [:index, :create]

        scope "/posts/:post_id" do
          resources "/comments", CommentController, only: [:create]
        end

        # Initiate upload — family context required
        post "/uploads/init", UploadController, :init_upload

        # Create conversation
        post "/conversations", ConversationController, :create

        # Create event
        post "/events", EventController, :create
      end
    end
  end

  # Local blob upload/download (signed token auth, no Bearer token required)
  scope "/api/v1", ShareCircleWeb.Api.V1 do
    put "/local-blob/:token", LocalBlobController, :upload
    get "/local-blob/:token", LocalBlobController, :download
  end

  scope "/", ShareCircleWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ShareCircleWeb.UserAuth, :require_authenticated_user}] do
      live "/families", FamilySetupLive, :index
      live "/families/:family_id/feed", FeedLive, :index
      live "/families/:family_id/chat", ChatLive, :index
      live "/families/:family_id/chat/:conversation_id", ChatLive, :show
      live "/families/:family_id/events", EventsLive, :index
      live "/families/:family_id/onboarding", OnboardingLive, :index
      live "/invitations/:token/accept", AcceptInvitationLive, :index
      live "/notifications", NotificationsLive, :index
      live "/admin", AdminLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:share_circle, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ShareCircleWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ShareCircleWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", ShareCircleWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", ShareCircleWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    get "/users/log-in/:token", UserSessionController, :confirm
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
