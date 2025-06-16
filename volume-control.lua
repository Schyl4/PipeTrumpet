-- for tracking
local app_nodes = {}
local default_node_id = 0

app_om = ObjectManager {
    Interest {
        type = "node",
        Constraint {"media.class", "=", "Stream/Output/Audio"}
    }
}

function createAppSink(app_name)
    local unique_name = "App-Sink-" .. app_name:gsub("[^%w]", "-")
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
    
    if not node then
        Log:warning("Failed to create node for " .. app_name)
        return
    end
    
    local si_node = SessionItem("si-node")

    if not si_node:configure({
        ["item.node"] = node,
    }) then
        Log:warning("Failed to configure si-node for " .. app_name)
        return
    end

    si_node:register()
    
    local node_info = {
        node = node,
        si_node = si_node,
        app_name = app_name,
        node_name = unique_name,
        connection_count = 1,
    }

    app_nodes[app_name] = node_info

    si_node:activate(Feature.SessionItem.ACTIVE)
end

app_om:connect("object-added", function(om, node)
    local properties = node.properties
    local app_name = properties["application.name"]
    local stream_id = node.id
    
    Log:warning("New audio stream detected: " .. tostring(app_name) .. " (ID: " .. stream_id .. ")")
    
    if not app_nodes[app_name] then
        createAppSink(app_name)
    else
        Log:warning("Volume control sink already exists")
        app_nodes[app_name].connection_count = app_nodes[app_name].connection_count + 1
        Log:warning("Connection count for " .. app_name .. " : " .. app_nodes[app_name].connection_count)
    end
end)

app_om:connect("object-removed", function(om, node)
    local app_name = node.properties["application.name"]
    local node_info = app_nodes[app_name]

    app_nodes[app_name].connection_count = app_nodes[app_name].connection_count - 1
    Log:warning("Connection count for " .. app_name .. " : " .. app_nodes[app_name].connection_count)

    if node_info.connection_count <= 0 then
        if node_info.si_node then
            Log:warning("Destroying SessionItem: " .. node_info.node_name)
            node_info.si_node:deactivate(Feature.SessionItem.ACTIVE)
            app_nodes[node.id] = nil
        end

        if node_info.node then
            Log:warning("Destroying node: " .. node_info.node_name)
            node_info.node:request_destroy()
        end
    end
end)

app_om:activate()