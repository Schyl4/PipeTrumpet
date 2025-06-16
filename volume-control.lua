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
    
    -- First create the actual Node
    local node = Node("adapter", {
        ["factory.name"] = "support.null-audio-sink",
        ["node.name"] = unique_name,
        ["node.description"] = description,
        ["media.class"] = "Audio/Sink",
        ["audio.channels"] = 2,
        ["audio.position"] = "FL,FR",
        ["node.virtual"] = true,
    })
    
    if not node then
        Log:warning("Failed to create node for " .. app_name)
        return nil, nil
    end
    
    -- Then wrap it with si-node SessionItem
    local si_node = SessionItem("si-node")

    if not si_node:configure {
        ["item.node"] = node,  -- Pass the actual Node object
    } then
        Log.warning(si_node, "failed to configure si-node")
        return nil, nil
    end

    si_node:register()
    
    local node_info = {
        node = node,
        si_node = si_node,
        app_name = app_name,
        node_name = unique_name,
        stream = stream
    }
    app_nodes[stream_id] = node_info

    node:activate(Feature.SessionItem.ACTIVE)
    
    return si_node, unique_name
end

app_om:connect("object-added", function(om, stream)
    local properties = stream.properties
    local app_name = properties["application.name"]
    local stream_id = stream.id
    
    Log:warning("New audio stream detected: " .. tostring(app_name) .. " (ID: " .. stream_id .. ")")
    
    if app_name then
        local app_sink, node_name = createAppSink(app_name, stream_id, stream)
    else
        Log:warning("Stream " .. stream_id .. " has no application.name property")
    end
end)

app_om:connect("object-removed", function(om, stream)
    local stream_id = stream.id
    local app_info = app_nodes[stream_id]
    
    if app_info then
        Log:warning("Test: " .. app_info.app_name .. " (ID: " .. stream_id .. ")")
        Log:warning("Stream disconnected: " .. app_info.app_name .. " (ID: " .. stream_id .. ")")
        
        -- Clean up input link (stream -> app sink)
        if app_info.input_link then
            Log:warning("Removing input link for " .. app_info.node_name)
            app_info.input_link:request_destroy()
            app_info.input_link = nil
        end
        
        -- Clean up output link (app sink -> default)
        if app_info.output_link then
            Log:warning("Removing output link for " .. app_info.node_name)
            app_info.output_link:request_destroy()
            app_info.output_link = nil
        end
        
        -- Destroy the associated virtual sink
        if app_info.si_node then
            Log:warning("Destroying SessionItem: " .. app_info.node_name)
            app_info.si_node:deactivate(Feature.SessionItem.ACTIVE)
            app_info.si_node = nil
        end
        
        -- Destroy the node
        if app_info.node then
            Log:warning("Destroying node: " .. app_info.node_name)
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