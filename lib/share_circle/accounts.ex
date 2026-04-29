defmodule ShareCircle.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias ShareCircle.Repo

  alias ShareCircle.Accounts.{User, UserNotifier, UserToken}
  alias ShareCircle.Families.Membership

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Returns the total number of non-deleted users in the system."
  def count_users, do: Repo.aggregate(from(u in User, where: is_nil(u.deleted_at)), :count)

  @doc "Promotes a user to instance admin."
  def make_admin!(%User{} = user) do
    user |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> maybe_make_first_admin()
    |> Repo.insert()
  end

  @doc "Registers a user with an email, display_name, and password (for API/password-based auth)."
  def register_user_with_password(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> maybe_make_first_admin()
    |> Repo.insert()
  end

  defp maybe_make_first_admin(changeset) do
    if count_users() == 0 do
      Ecto.Changeset.put_change(changeset, :is_admin, true)
    else
      changeset
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `ShareCircle.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `ShareCircle.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  ## Password reset

  @doc "Sends a password-reset email. Always returns :ok — doesn't reveal whether the email exists."
  def deliver_user_reset_password_instructions(%User{} = user, reset_url_fun)
      when is_function(reset_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_reset_password_token(user)
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_url_fun.(encoded_token))
  end

  @doc "Validates the reset token and updates the password. Deletes all tokens on success."
  def reset_user_password(token, attrs) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         {%User{} = user, _token} <- Repo.one(query) do
      user
      |> User.password_changeset(attrs)
      |> update_user_and_delete_all_tokens()
    else
      _ -> {:error, :invalid_or_expired_token}
    end
  end

  ## Email confirmation

  @doc "Sends a confirmation email for password-based signups."
  def deliver_user_confirmation_instructions(%User{confirmed_at: nil} = user, confirm_url_fun)
      when is_function(confirm_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_confirmation_token(user)
    Repo.insert!(user_token)
    UserNotifier.deliver_confirmation_instructions(user, confirm_url_fun.(encoded_token))
  end

  def deliver_user_confirmation_instructions(%User{}, _fun), do: {:error, :already_confirmed}

  @doc "Confirms the user's email address via the token sent in the confirmation email."
  def confirm_user_email(token) do
    with {:ok, query} <- UserToken.verify_confirmation_token_query(token),
         {%User{} = user, token_record} <- Repo.one(query) do
      Repo.transaction(fn ->
        Repo.delete!(token_record)
        {:ok, user} = Repo.update(User.confirm_changeset(user))
        user
      end)
    else
      _ -> {:error, :invalid_or_expired_token}
    end
  end

  ## API tokens

  @doc "Generates a long-lived API token for the user. Returns the raw token string."
  def generate_user_api_token(user) do
    {token, user_token} = UserToken.build_api_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Looks up the user by a raw API Bearer token. Returns %User{} or nil."
  def get_user_by_api_token(token) when is_binary(token) do
    case UserToken.verify_api_token_query(token) do
      {:ok, query} -> Repo.one(query)
      _ -> nil
    end
  end

  @doc "Deletes the API token identified by its raw value (used for logout)."
  def delete_user_api_token(raw_token) when is_binary(raw_token) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(:sha256, decoded)
        Repo.delete_all(from(UserToken, where: [token: ^hashed, context: "api"]))
        :ok

      :error ->
        :ok
    end
  end

  @doc "Lists all active API tokens for a user (for session management UI)."
  def list_user_api_tokens(%User{id: user_id}) do
    UserToken.by_user_api_tokens_query(user_id)
    |> Repo.all()
  end

  @doc "Deletes a specific API token by ID, only if owned by the given user."
  def delete_user_api_token_by_id(%User{id: user_id}, token_id) do
    case Repo.get_by(UserToken, id: token_id, user_id: user_id, context: "api") do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  ## Supervised accounts

  @doc """
  Creates a supervised (child) account on behalf of the given guardian user.

  The child has no password at creation — they activate their account via email.
  Returns `{:ok, %User{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def create_child_account(%User{} = guardian, attrs) do
    %User{}
    |> User.supervised_registration_changeset(Map.put(attrs, "guardian_user_id", guardian.id))
    |> Repo.insert()
  end

  @doc "Sends the child their account activation email (link valid 7 days)."
  def deliver_child_activation_instructions(%User{} = child, guardian_display_name, url_fun)
      when is_function(url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_child_activation_token(child)
    Repo.insert!(user_token)

    UserNotifier.deliver_child_activation_instructions(
      child,
      guardian_display_name,
      url_fun.(encoded_token)
    )
  end

  @doc """
  Completes child account activation: sets a password and confirms the account.

  Returns `{:ok, %User{}}` or `{:error, changeset | :invalid_or_expired_token}`.
  """
  def complete_child_activation(token, attrs) do
    with {:ok, query} <- UserToken.verify_child_activation_token_query(token),
         {%User{} = user, _token_record} <- Repo.one(query) do
      Repo.transact(fn ->
        with {:ok, activated_user} <-
               user |> User.activation_changeset(attrs) |> Repo.update() do
          Repo.delete_all(from(t in UserToken, where: t.user_id == ^activated_user.id))
          {:ok, activated_user}
        end
      end)
    else
      _ -> {:error, :invalid_or_expired_token}
    end
  end

  @doc "Sends the child a promotion email (link valid 7 days). Caller must be guardian/admin/owner."
  def deliver_promotion_instructions(%User{} = child, guardian_display_name, url_fun)
      when is_function(url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_promotion_token(child)
    Repo.insert!(user_token)

    UserNotifier.deliver_promotion_instructions(
      child,
      guardian_display_name,
      url_fun.(encoded_token)
    )
  end

  @doc """
  Completes promotion: sets a new password, optionally changes email, clears `is_supervised`,
  records `promoted_at`, bumps all `child` memberships to `member`, and deletes all tokens.

  Notifies the guardian by email afterward (best-effort, outside the transaction).

  Returns `{:ok, %User{}}` or `{:error, changeset | :invalid_or_expired_token}`.
  """
  def complete_promotion(token, attrs) do
    with {:ok, query} <- UserToken.verify_promotion_token_query(token),
         {%User{} = user, _token_record} <- Repo.one(query) do
      result =
        Repo.transact(fn ->
          with {:ok, promoted_user} <-
                 user |> User.promotion_changeset(attrs) |> Repo.update() do
            Repo.delete_all(from(t in UserToken, where: t.user_id == ^promoted_user.id))

            Repo.update_all(
              from(m in Membership, where: m.user_id == ^promoted_user.id and m.role == "child"),
              set: [role: "member"]
            )

            {:ok, promoted_user}
          end
        end)

      with {:ok, promoted_user} <- result do
        maybe_notify_guardian(promoted_user)
      end

      result
    else
      _ -> {:error, :invalid_or_expired_token}
    end
  end

  @doc """
  Generates a short-lived magic-link login token for a user who just activated or
  was promoted. The token can be used once at `GET /users/log-in/:token` to log
  the user in without requiring them to re-enter their password.
  """
  def generate_post_activation_login_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    encoded_token
  end

  defp maybe_notify_guardian(%User{guardian_user_id: nil}), do: :ok

  defp maybe_notify_guardian(%User{guardian_user_id: guardian_id} = promoted_user) do
    case Repo.get(User, guardian_id) do
      nil ->
        :ok

      guardian ->
        UserNotifier.deliver_promotion_complete_notification(guardian, promoted_user.display_name)
    end
  end

  @doc "Updates the user's profile fields (display_name, bio, location, birthday, interests, avatar, cover, pinned_post, timezone, locale)."
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc "Soft-deletes the user and revokes all their tokens."
  def soft_delete_user(%User{} = user) do
    Repo.transaction(fn ->
      Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id))

      {:ok, user} =
        Repo.update(Ecto.Changeset.change(user, deleted_at: DateTime.utc_now(:microsecond)))

      user
    end)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
