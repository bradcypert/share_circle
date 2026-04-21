defmodule ShareCircleWeb.Api.V1.ApiSpec do
  @moduledoc "Top-level OpenAPI 3.1 specification for the ShareCircle v1 API."

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, SecurityScheme, Server}

  @impl OpenApi
  def spec do
    %OpenApi{
      openapi: "3.1.0",
      info: %Info{
        title: "ShareCircle API",
        version: "1.0.0",
        description: "Private family social network API. All endpoints require Bearer authentication."
      },
      servers: [
        %Server{url: "/api/v1", description: "Current version"}
      ],
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "Opaque API token. Obtain via POST /api/v1/auth/token."
          }
        }
      },
      paths: %{}
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
