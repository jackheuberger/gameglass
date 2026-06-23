defmodule Gameglass.Catalog.Client do
  @moduledoc """
  Thin client over the **anonymous, public** Xbox catalog endpoints used to build
  Gameglass. No authentication or Xbox user token (xuid) is required.

    * Enumerate the full cloud catalog via the "All games" SIGL collection that
      backs `play.xbox.com/gallery/all-games`.
    * Enrich each product via `catalog.gamepass.com/v3/products` with the
      `RemoteHighSapphire0` hydration, which returns `XCloudTitleId`,
      `XCloudOfferings.CLOUDGAMING.Programs`, `PassMetadataByPassProductId`,
      `AnonymousPrice`, and metadata.

  All endpoints, ids and tunables are overridable via application config under
  `config :gameglass, Gameglass.Catalog.Client, ...`.
  """

  require Logger

  @defaults [
    sigl_base: "https://catalog.gamepass.com",
    all_games_sigl_id: "1bf84c2b-0643-4591-893f-d9edb703f692",
    hydration: "RemoteHighSapphire0",
    market: "US",
    language: "en-us",
    batch_size: 50,
    calling_app_name: "Gameglass",
    calling_app_version: "1.0"
  ]

  @doc ~S'Returns `{:ok, [product_id]}` for every title in the cloud "All games" collection.'
  def fetch_all_game_ids(opts \\ []) do
    cfg = config(opts)

    url = "#{cfg[:sigl_base]}/sigls/v2"

    params = [
      id: cfg[:all_games_sigl_id],
      market: cfg[:market],
      language: cfg[:language]
    ]

    case request(:get, url, params: params, opts: opts) do
      {:ok, body} when is_list(body) ->
        ids =
          body
          |> Enum.filter(&is_map/1)
          |> Enum.flat_map(fn
            %{"id" => id} when is_binary(id) -> [id]
            _ -> []
          end)
          |> Enum.uniq()

        {:ok, ids}

      {:ok, other} ->
        {:error, {:unexpected_sigl_body, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns `{:ok, [product_id]}` for every title in any subscription plan
  (`/subscriptions?subscription=all`). This catches cloud titles the gallery
  SIGL omits (e.g. EA Play titles, some first-party games). Console/PC-only
  entries are filtered out later by the absence of a `CLOUDGAMING` offering.
  """
  def fetch_subscription_ids(opts \\ []) do
    cfg = config(opts)

    url = "#{cfg[:sigl_base]}/subscriptions"
    params = [market: cfg[:market], subscription: "all", language: cfg[:language]]

    case request(:get, url, params: params, opts: opts) do
      {:ok, body} when is_map(body) ->
        ids =
          body
          |> Map.values()
          |> List.flatten()
          |> Enum.filter(&is_binary/1)
          |> Enum.uniq()

        {:ok, ids}

      {:ok, other} ->
        {:error, {:unexpected_subscriptions_body, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The full candidate set of cloud product ids: the union of the "All games" SIGL
  and every subscription plan. The SIGL is authoritative for enumeration; the
  subscription list is best-effort (a failure there is logged and ignored).
  """
  def fetch_catalog_ids(opts \\ []) do
    with {:ok, sigl_ids} <- fetch_all_game_ids(opts) do
      sub_ids =
        case fetch_subscription_ids(opts) do
          {:ok, ids} ->
            ids

          {:error, reason} ->
            Logger.warning("Gameglass: /subscriptions enumeration failed: #{inspect(reason)}")
            []
        end

      {:ok,
       %{
         ids: Enum.uniq(sigl_ids ++ sub_ids),
         sigl: length(sigl_ids),
         subscriptions: length(sub_ids)
       }}
    end
  end

  @doc """
  Enriches a list of product ids. Returns `{:ok, %{product_id => product_map}}`.

  Requests are issued in batches; a failed batch aborts with `{:error, reason}`.
  """
  def fetch_products(product_ids, opts \\ [])
  def fetch_products([], _opts), do: {:ok, %{}}

  def fetch_products(product_ids, opts) do
    cfg = config(opts)

    url =
      "#{cfg[:sigl_base]}/v3/products?" <>
        URI.encode_query(
          market: cfg[:market],
          language: cfg[:language],
          hydration: cfg[:hydration]
        )

    headers = [
      {"ms-cv", correlation_vector()},
      {"calling-app-name", cfg[:calling_app_name]},
      {"calling-app-version", cfg[:calling_app_version]}
    ]

    product_ids
    |> Enum.uniq()
    |> Enum.chunk_every(cfg[:batch_size])
    |> Enum.reduce(%{}, fn batch, acc ->
      case request(:post, url, json: %{"Products" => batch}, headers: headers, opts: opts) do
        {:ok, %{"Products" => products}} when is_map(products) ->
          Map.merge(acc, products)

        {:ok, other} ->
          Logger.warning("Gameglass: unexpected /v3/products body: #{inspect(other)}")
          acc

        {:error, reason} ->
          Logger.warning(
            "Gameglass: /v3/products batch failed (#{length(batch)} ids): #{inspect(reason)}"
          )

          acc
      end
    end)
    |> then(&{:ok, &1})
  end

  @doc "Generates a fresh MS correlation vector (base CV)."
  def correlation_vector do
    base =
      11
      |> :crypto.strong_rand_bytes()
      |> Base.encode64()
      |> String.replace("=", "")

    base <> ".0"
  end

  defp request(method, url, kwopts) do
    {req_opts, _} = Keyword.split(kwopts, [:params, :json, :headers])
    user_opts = Keyword.get(kwopts, :opts, [])

    base =
      [
        method: method,
        url: url,
        retry: :transient,
        max_retries: 3,
        receive_timeout: 30_000,
        user_agent: "Gameglass/1.0 (+https://github.com/gameglass)"
      ]
      |> Keyword.merge(req_opts)
      |> Keyword.merge(Keyword.get(user_opts, :req_options, []))

    try do
      resp = Req.request!(base)

      case resp.status do
        status when status in 200..299 -> {:ok, resp.body}
        status -> {:error, {:http_status, status, resp.body}}
      end
    rescue
      e -> {:error, {:request_failed, Exception.message(e)}}
    end
  end

  defp config(opts) do
    @defaults
    |> Keyword.merge(Application.get_env(:gameglass, __MODULE__, []))
    |> Keyword.merge(Keyword.take(opts, Keyword.keys(@defaults)))
  end
end
