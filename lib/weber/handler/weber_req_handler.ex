defmodule Handler.WeberReqHandler do
    
    @moduledoc """
        Weber http request cowboy handler.
    """

    import Weber.Route
    import Weber.Http.Url
    import Handler.Weber404Handler

    defrecord State, 
        app_name: nil

    def init(_transport, req, name) do
        {:ok, req, State.new app_name: name}
    end

    def handle(req, state) do
        # get method
        {method, req2} = :cowboy_req.method(req)
        # get path
        {path, req3} = :cowboy_req.path(req2)

        routes = :gen_server.call(state.app_name, :routes)
        static = :gen_server.call(state.app_name, :static)
        views = :gen_server.call(state.app_name,  :views)
        root = :gen_server.call(state.app_name,  :root)
        
        successful_route = :lists.flatten(match_routes(path, routes))
        
        case successful_route do
            [] -> 
                res = try_to_find_static_resource(path, static, views, root)
                case res do
                    404 ->
                        :cowboy_req.reply(200, [], get404, req3)
                    _ ->
                        {:ok, data} = File.read(res)
                        {:ok, _req4} = :cowboy_req.reply(200, [], data, req3)
                end                
            [{:path, path}, {:controller, controller}, {:action, action}] ->
                bindings = getAllBinding(path)
                f = Module.function(controller, action, 2)
                result = f.(method, bindings)
                res = handle_result(result, controller, views)
                {:ok, _req4} = :cowboy_req.reply(200, [], res, req3)
        end

        {:ok, req, state}
    end

    def terminate(_reason, _req, _state) do
        :ok
    end

    @doc """
        Handle response from controller
    """
    def handle_result(res, controller, views) do
        c = atom_to_list(controller)
        filename = :erlang.binary_to_list(String.downcase(:erlang.list_to_binary(List.last(:string.tokens(c, '.')) ++ ".html")))
        case res do
            {:render, data} -> 
                views_filenames = get_all_files(views)
                view_file = Enum.filter(views_filenames, fn(file) ->
                                              Path.basename(file) == filename
                                          end)
                {:ok, d} = File.read(:lists.nth(1, view_file))
                EEx.eval_string d, data
            {:json, data} ->
                JSON.generate(data)
        end
    end

    @doc """
        Try to find static resource and send response
    """
    def try_to_find_static_resource(path, static, views, _root) do
        p = :erlang.binary_to_list(path)
        resource = List.last(:string.tokens(p, '/'))

        views_filenames = get_all_files(views)
        static_filenames = get_all_files(static)

        view_file = Enum.filter(views_filenames, fn(filename) ->
                                Path.basename(filename) == resource
                                end)

        static_file = Enum.filter(static_filenames, fn(filename) ->
                                  Path.basename(filename) == resource
                                  end)
           
        case view_file do
            [] ->
                case static_file do
                    [] ->
                        404
                    [resource_name] ->
                        resource_name
                end
            [resource_name] ->
                resource_name
        end
    end

    @doc """
        Recursively get all files from directory.
    """
    def get_all_files(dir) do
        find_files = fn(f, acc) -> [f | acc] end
        :filelib.fold_files(dir, ".*", true, find_files, [])
    end

end