defmodule Mix.Ecto do
  # Conveniences for writing Mix.Tasks in Ecto.
  @moduledoc false

  @doc """
  Parses the repository option from the given list.

  If no repo option is given, we get one from the environment.
  """
  @spec parse_repo([term]) :: [Ecto.Repo.t]
  def parse_repo(args) do
    parse_repo(args, [])
  end

  defp parse_repo([key, value|t], acc) when key in ~w(--repo -r) do
    parse_repo t, [Module.concat([value])|acc]
  end

  defp parse_repo([_|t], acc) do
    parse_repo t, acc
  end

  defp parse_repo([], []) do
    app = Mix.Project.config[:app]

    cond do
      repos = Application.get_env(app, :ecto_repos) ->
        repos

      # TODO: Remove function exported check once we depend on 1.3 only
      not function_exported?(Mix.Project, :deps_paths, 0) or
          Map.has_key?(Mix.Project.deps_paths, :ecto) ->
        Mix.shell.error """
        warning: could not find repositories for application #{inspect app}.

        You can avoid this warning by passing the -r flag or by setting the
        repositories managed by this application in your config/config.exs:

            config #{inspect app}, ecto_repos: [...]

        The configuration may be an empty list if it does not define any repo.
        """
        []

      true ->
        []

    end
  end

  defp parse_repo([], acc) do
    Enum.reverse(acc)
  end

  @doc """
  Ensures the given module is a repository.
  """
  @spec ensure_repo(module, list) :: Ecto.Repo.t | no_return
  def ensure_repo(repo, args) do
    Mix.Task.run "loadpaths", args

    unless "--no-compile" in args do
      Mix.Project.compile(args)
    end

    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__adapter__, 0) do
          repo
        else
          Mix.raise "Module #{inspect repo} is not an Ecto.Repo. " <>
                    "Please configure your app accordingly or pass a repo with the -r option."
        end
      {:error, error} ->
        Mix.raise "Could not load #{inspect repo}, error: #{inspect error}. " <>
                  "Please configure your app accordingly or pass a repo with the -r option."
    end
  end

  @doc """
  Ensures the given repository is started and running.
  """
  @spec ensure_started(Ecto.Repo.t, Keyword.t) :: {:ok, pid, [atom]} | no_return
  def ensure_started(repo, opts) do
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, apps} = repo.__adapter__.ensure_all_started(repo, :temporary)

    pool_size = Keyword.get(opts, :pool_size, 1)
    case repo.start_link(pool_size: pool_size) do
      {:ok, pid} ->
        {:ok, pid, apps}
      {:error, {:already_started, _pid}} ->
        {:ok, nil, apps}
      {:error, error} ->
        Mix.raise "Could not start repo #{inspect repo}, error: #{inspect error}"
    end
  end

  @doc """
  Ensures the given repository's migrations path exists on the filesystem.
  """
  @spec ensure_migrations_path(Ecto.Repo.t) :: Ecto.Repo.t | no_return
  def ensure_migrations_path(repo) do
    with false <- Mix.Project.umbrella?,
         path = Path.relative_to(migrations_path(repo), Mix.Project.app_path),
         false <- File.dir?(path),
         do: Mix.raise "Could not find migrations directory #{inspect path} for repo #{inspect repo}"
    repo
  end

  @doc """
  Restarts the app if there was any migration command.
  """
  @spec restart_apps_if_migrated([atom], list()) :: :ok
  def restart_apps_if_migrated(_apps, []), do: :ok
  def restart_apps_if_migrated(apps, [_|_]) do
    # Silence the logger to avoid application down messages.
    Logger.remove_backend(:console)
    for app <- Enum.reverse(apps) do
      Application.stop(app)
    end
    for app <- apps do
      Application.ensure_all_started(app)
    end
    :ok
  after
    Logger.add_backend(:console, flush: true)
  end

  @doc """
  Gets the migrations path from a repository.
  """
  @spec migrations_path(Ecto.Repo.t) :: String.t
  def migrations_path(repo) do
    Path.join(build_repo_priv(repo), "migrations")
  end

  @doc """
  Returns the private repository path relative to the source.
  """
  def source_repo_priv(repo) do
    repo.config()[:priv] || "priv/#{repo |> Module.split |> List.last |> Macro.underscore}"
  end

  @doc """
  Returns the private repository path inside build.
  """
  def build_repo_priv(repo) do
    Application.app_dir(Keyword.fetch!(repo.config(), :otp_app), source_repo_priv(repo))
  end

  @doc """
  Asks if the user wants to open a file based on ECTO_EDITOR.
  """
  @spec open?(binary) :: boolean
  def open?(file) do
    editor = System.get_env("ECTO_EDITOR") || ""
    if editor != "" do
      :os.cmd(to_char_list(editor <> " " <> inspect(file)))
      true
    else
      false
    end
  end

  @doc """
  Gets a path relative to the application path.
  Raises on umbrella application.
  """
  def no_umbrella!(task) do
    if Mix.Project.umbrella? do
      Mix.raise "Cannot run task #{inspect task} from umbrella application"
    end
  end

  @doc """
  Returns `true` if module implements behaviour.
  """
  def ensure_implements(module, behaviour, message) do
    all = Keyword.take(module.__info__(:attributes), [:behaviour])
    unless [behaviour] in Keyword.values(all) do
      Mix.raise "Expected #{inspect module} to implement #{inspect behaviour} " <>
                "in order to #{message}"
    end
  end
end
