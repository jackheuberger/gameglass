defmodule GameglassWeb.GamesLive do
  @moduledoc """
  The comparison matrix: every cloud-streamable game as a row, with a column per
  subscription tier showing whether it is included, purchase-required, or
  unavailable. Backed by LiveView streams with server-side filtering, sorting and
  pagination.
  """
  use GameglassWeb, :live_view

  alias Gameglass.Catalog
  alias Gameglass.Catalog.Links
  alias Gameglass.Ingest.Refresher

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Gameglass.PubSub, Refresher.topic())

    {:ok,
     socket
     |> assign(:tiers, Catalog.tiers())
     |> assign(:stats, Catalog.stats())
     |> assign(:ingest_status, Refresher.status())
     |> assign(:page_title, "xCloud streamability")
     |> stream(:games, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    page = parse_page(params)

    result =
      Catalog.list_games(
        page: page,
        per_page: @per_page,
        search: filters.search,
        streamable_on: blank_nil(filters.streamable_on),
        purchase_on: blank_nil(filters.purchase_on),
        f2p_only: filters.f2p_only,
        recently_changed: filters.recently_changed,
        sort: sort_for(filters)
      )

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters_to_params(filters), as: :filters))
     |> assign(:page, result.page)
     |> assign(:total, result.total)
     |> assign(:total_pages, result.total_pages)
     |> assign(:per_page, result.per_page)
     |> stream(:games, result.games, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    # Reset to page 1 whenever filters change.
    {:noreply, push_patch(socket, to: ~p"/?#{query_params(params, 1)}")}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    params = filters_to_params(socket.assigns.filters)
    {:noreply, push_patch(socket, to: ~p"/?#{query_params(params, page)}")}
  end

  def handle_event("refresh", _params, socket) do
    case Refresher.refresh_async() do
      :ok ->
        {:noreply,
         socket
         |> assign(:ingest_status, :running)
         |> put_flash(:info, "Refreshing the catalog from Xbox… this can take a minute.")}

      :already_running ->
        {:noreply, assign(socket, :ingest_status, :running)}
    end
  end

  @impl true
  def handle_info({:ingest, :started}, socket) do
    {:noreply, assign(socket, :ingest_status, :running)}
  end

  def handle_info({:ingest, {:finished, summary}}, socket) do
    {:noreply,
     socket
     |> assign(:ingest_status, :idle)
     |> assign(:stats, Catalog.stats())
     |> put_flash(
       :info,
       "Catalog refreshed: #{summary.cloud_titles} games (+#{summary.added} new, #{summary.changed} changed)."
     )
     |> push_patch(to: ~p"/?#{filters_to_params(socket.assigns.filters)}")}
  end

  def handle_info({:ingest, {:failed, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ingest_status, :idle)
     |> put_flash(:error, "Catalog refresh failed. Check the server logs.")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- params helpers --------------------------------------------------------

  defp parse_filters(params) do
    %{
      search: Map.get(params, "search", ""),
      streamable_on: Map.get(params, "streamable_on", ""),
      purchase_on: Map.get(params, "purchase_on", ""),
      f2p_only: truthy?(Map.get(params, "f2p_only")),
      recently_changed: truthy?(Map.get(params, "recently_changed"))
    }
  end

  defp parse_page(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp sort_for(%{recently_changed: true}), do: :recent
  defp sort_for(_), do: :recent

  defp truthy?(v), do: v in ["true", "on", "1", true]
  defp blank_nil(""), do: nil
  defp blank_nil(v), do: v

  defp filters_to_params(filters) do
    %{
      "search" => filters.search,
      "streamable_on" => filters.streamable_on,
      "purchase_on" => filters.purchase_on,
      "f2p_only" => to_string(filters.f2p_only),
      "recently_changed" => to_string(filters.recently_changed)
    }
  end

  # Build a compact query param map (drop empties) for shareable URLs.
  defp query_params(params, page) do
    params
    |> Map.take(~w(search streamable_on purchase_on f2p_only recently_changed))
    |> Map.put("page", to_string(page))
    |> Enum.reject(fn {_k, v} -> v in ["", "false", nil] end)
    |> Map.new()
  end

  # --- view helpers ----------------------------------------------------------

  @doc false
  def status_cell(assigns) do
    {label, classes, icon} = status_style(assigns.status)
    assigns = assign(assigns, label: label, classes: classes, icon: icon)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium whitespace-nowrap",
      @classes
    ]}>
      <.icon name={@icon} class="size-3.5" />
      <span class="hidden md:inline">{@label}</span>
    </span>
    """
  end

  defp status_style("included"),
    do:
      {"Included", "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
       "hero-check-circle"}

  defp status_style("purchase"),
    do: {"Purchase", "bg-amber-500/15 text-amber-600 dark:text-amber-400", "hero-shopping-cart"}

  defp status_style("free"),
    do: {"Free", "bg-sky-500/15 text-sky-600 dark:text-sky-400", "hero-gift"}

  defp status_style("unavailable"),
    do: {"Unavailable", "bg-rose-500/10 text-rose-500/80", "hero-x-circle"}

  defp status_style(_unknown),
    do: {"Unknown", "bg-base-content/5 text-base-content/40", "hero-question-mark-circle"}

  @doc false
  def game_links(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-0.5">
      <a
        href={Links.play_new(@game.base_product_id, @game.title)}
        target="_blank"
        rel="noopener"
        title="Stream on play.xbox.com (new client)"
        class="rounded p-1.5 text-base-content/40 transition-colors hover:bg-base-200 hover:text-primary"
      >
        <.icon name="hero-cloud" class="size-4" />
      </a>
      <a
        href={Links.play_legacy(@game.base_product_id, @game.title)}
        target="_blank"
        rel="noopener"
        title="Stream on xbox.com/play (legacy client)"
        class="rounded p-1.5 text-base-content/40 transition-colors hover:bg-base-200 hover:text-primary"
      >
        <.icon name="hero-play" class="size-4" />
      </a>
      <a
        href={Links.store(@game.base_product_id, @game.title)}
        target="_blank"
        rel="noopener"
        title="View in the Xbox Store"
        class="rounded p-1.5 text-base-content/40 transition-colors hover:bg-base-200 hover:text-primary"
      >
        <.icon name="hero-building-storefront" class="size-4" />
      </a>
    </div>
    """
  end

  defp status_map(game), do: Catalog.status_map(game)

  defp tier_status(game, tier_key), do: Map.get(status_map(game), tier_key, "unknown")

  defp tier_options(tiers), do: Enum.map(tiers, &{tier_short_name(&1), &1.key})

  defp tier_short_name(%{name: name}), do: String.replace_prefix(name, "Game Pass ", "")

  defp active_filters?(filters) do
    filters.search != "" or filters.streamable_on != "" or filters.purchase_on != "" or
      filters.f2p_only or filters.recently_changed
  end
end
