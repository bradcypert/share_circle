defmodule ShareCircleWeb.PageController do
  use ShareCircleWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
