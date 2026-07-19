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

  alias Gameglass.Catalog.Types.RawProduct

  @defaults [
    sigl_base: "https://catalog.gamepass.com",
    all_games_sigl_id: "1bf84c2b-0643-4591-893f-d9edb703f692",
    hydration: "RemoteHighSapphire0",
    market: "US",
    language: "en-us",
    batch_size: 50,
    calling_app_name: "Gameglass",
    calling_app_version: "0.1"
  ]

  @type product_index :: %{String.t() => RawProduct.t()}

  @doc ~S'Returns `{:ok, [product_id]}` for every title in the cloud "All games" collection.'
  @spec fetch_all_game_ids(keyword()) :: {:ok, [String.t()]} | {:error, term()}
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
  @spec fetch_subscription_ids(keyword()) :: {:ok, [String.t()]} | {:error, term()}
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
  @spec fetch_catalog_ids(keyword()) ::
          {:ok, %{ids: [String.t()], sigl: non_neg_integer(), subscriptions: non_neg_integer()}}
          | {:error, term()}
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
  Enriches product ids and converts each API document to a `RawProduct`.

  Requests are issued in batches; a failed batch aborts with `{:error, reason}`.
  """
  @spec fetch_products([String.t()], keyword()) ::
          {:ok, product_index()} | {:error, term()}
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
      {"ms-cv", "cv"},
      {"calling-app-name", cfg[:calling_app_name]},
      {"calling-app-version", cfg[:calling_app_version]}
    ]

    product_ids
    |> Enum.uniq()
    |> Enum.chunk_every(cfg[:batch_size])
    |> Enum.reduce_while({:ok, %{}}, fn batch, {:ok, acc} ->
      case request(:post, url, json: %{"Products" => batch}, headers: headers, opts: opts) do
        {:ok, %{"Products" => products}} when is_map(products) ->
          case parse_products(products) do
            {:ok, parsed} -> {:cont, {:ok, Map.merge(acc, parsed)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:ok, other} ->
          {:halt, {:error, {:unexpected_products_body, other}}}

        {:error, reason} ->
          {:halt, {:error, {:products_batch_failed, length(batch), reason}}}
      end
    end)
  end

  @spec parse_products(map()) :: {:ok, product_index()} | {:error, term()}
  defp parse_products(products) do
    Enum.reduce_while(products, {:ok, %{}}, fn
      {product_id, payload}, {:ok, acc} when is_binary(product_id) and is_map(payload) ->
        product = RawProduct.from_json(product_id, payload)
        {:cont, {:ok, Map.put(acc, product_id, product)}}

      {product_id, _payload}, _acc ->
        {:halt, {:error, {:invalid_product_payload, product_id}}}
    end)
  end

  @doc "The configured Xbox catalog market for this scan."
  @spec market(keyword()) :: String.t()
  def market(opts \\ []), do: config(opts)[:market]

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
        user_agent: "Gameglass/0.2 (+https://github.com/jackheuberger/gameglass)"
      ]
      |> Keyword.merge(req_opts)
      |> Keyword.merge(Keyword.get(user_opts, :req_options, []))

    case Req.request(base) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, error} ->
        {:error, {:request_failed, Exception.message(error)}}
    end
  end

  defp config(opts) do
    @defaults
    |> Keyword.merge(Application.get_env(:gameglass, __MODULE__, []))
    |> Keyword.merge(Keyword.take(opts, Keyword.keys(@defaults)))
  end
end
