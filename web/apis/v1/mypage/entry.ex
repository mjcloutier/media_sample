defmodule MediaSample.API.V1.Mypage.Entry do
  use Maru.Router
  import Phoenix.View, only: [render: 3], warn: false
  alias MediaSample.{Repo, Entry, Category, API.EntryView, UserAuthService, EntryService}, warn: false
  helpers MediaSample.API.V1.SharedParams

  plug Guardian.Plug.EnsureAuthenticated, handler: MediaSample.API.V1.Session

  def check_user_permission!(user) do
    unless UserAuthService.editable_user?(user), do: raise "user doesn't have authority to post an entry."
  end

  def check_owner!(entry, user) do
    unless entry.user.id == user.id, do: raise "user is not the owner of this entry."
  end

  resource "/entry" do
    params do
      use [:entry]
    end
    post "/save" do
      user = Guardian.Plug.current_resource(conn)
      check_user_permission!(user)
      _ = Category |> Category.valid |> Repo.slave.get!(params.category_id) # only check if valid category exists.

      params = Guardian.Utils.stringify_keys(params)
      locale = conn.assigns.locale

      multi = if !Map.has_key?(params, "id") do
        params = Map.put(params, "user_id", user.id)
        changeset = Entry.changeset(%Entry{}, params)
        EntryService.insert(changeset, params, locale)
      else
        entry = Entry |> Entry.preload_all(locale) |> Repo.slave.get!(params["id"])
        check_owner!(entry, user)
        changeset = Entry.changeset(entry, params)
        EntryService.update(changeset, params, locale)
      end

      case Repo.transaction(multi) do
        # remarks: if file parameter isn't passed, `upload` is nil (:upload multi isn't executed).
        # otherwise, should pass `upload` to view to get uploaded file path.
        {:ok, %{entry: entry, upload: upload}} ->
          conn
          |> json(render(EntryView, "show.json", entry: upload || entry))
        {:error, _failed_operation, _failed_value, _changes_so_far} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Entry save failed"})
      end
    end

    params do
      use [:id]
    end
    get ":id" do
      entry = Entry |> Entry.preload_all(conn.assigns.locale) |> Repo.slave.get!(params[:id])
      conn |> json(render(EntryView, "show.json", entry: entry))
    end
  end
end
