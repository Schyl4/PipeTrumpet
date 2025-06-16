
-- for tracking
local app_nodes = {}
local default_node_id = 0

app_om = ObjectManager {
    Interest {
        type = "node",
        Constraint {"media.class", "=", "Stream/Output/Audio"}
    }
}

function createAppSink(app_name, stream_id, stream)
    local unique_name = "app-sink-" .. app_name:gsub("[^%w]", "-") .. "-" .. stream_id
    local description = "Volume Control for " .. app_name
    
    local node = Node("adapter", {
        ["factory.name"] = "support.null-audio-sink",
        ["node.name"] = unique_name,
        ["node.description"] = description,
        ["media.class"] = "Audio/Sink",
        ["audio.channels"] = 2,
        ["audio.position"] = "FL,FR",
        ["node.virtual"] = true,
    })
    
    if node then
        local node_info = {
            node = node,
            app_name = app_name,
            node_name = unique_name,
            stream = stream
        }
        app_nodes[stream_id] = node_info
        
        node:activate(Feature.Proxy.BOUND, function(n, error)
            if error then
                Log:warning("Failed to activate sink for " .. app_name .. ": " .. tostring(error))
                -- Clean up on failure
                app_nodes[stream_id] = nil
            else
                Log:info("Created virtual sink for " .. app_name .. ": " .. unique_name)
                
            end
        end)
        return node, unique_name
    else
        Log:warning("Failed to create sink for " .. app_name)
        return nil, nil
    end
end

app_om:connect("object-added", function(om, stream)
    local properties = stream.properties
    local app_name = properties["application.name"]
    local stream_id = stream.id
    
    Log:info("New audio stream detected: " .. tostring(app_name) .. " (ID: " .. stream_id .. ")")
    
    if app_name then
        local app_sink, node_name = createAppSink(app_name, stream_id, stream)
    else
        Log:warning("Stream " .. stream_id .. " has no application.name property")
    end
end)

app_om:connect("object-removed", function(om, stream)
    local stream_id = stream.id
    local app_info = app_nodes[stream_id]
    Log:info("Test: " .. app_info.app_name .. " (ID: " .. stream_id .. ")")
    
    if app_info then
        Log:info("Stream disconnected: " .. app_info.app_name .. " (ID: " .. stream_id .. ")")
        
        -- Clean up input link (stream -> app sink)
        if app_info.input_link then
            Log:info("Removing input link for " .. app_info.node_name)
            app_info.input_link:request_destroy()
            app_info.input_link = nil
        end
        
        -- Clean up output link (app sink -> default)
        if app_info.output_link then
            Log:info("Removing output link for " .. app_info.node_name)
            app_info.output_link:request_destroy()
            app_info.output_link = nil
        end
        
        -- Destroy the associated virtual sink
        if app_info.node then
            Log:info("Destroying virtual sink: " .. app_info.node_name)
            app_info.node:request_destroy()
            app_info.node = nil
        end
        
        -- Remove from tracking
        app_nodes[stream_id] = nil
    else
        Log:debug("Untracked stream disconnected: " .. stream_id)
    end
end)

app_om:activate()