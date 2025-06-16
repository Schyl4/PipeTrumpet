-- for tracking
local app_nodes = {}
local default_node_id = 0

source_om = ObjectManager {
    Interest {
        type = "node",
        Constraint {"media.class", "=", "Stream/Output/Audio"}
    }
}

function createAppSink(source_name)
    local unique_name = "App-Sink-" .. source_name:gsub("[^%w]", "-")
    local description = "Volume Control for " .. source_name
    
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
        Log:warning("Failed to create node for " .. source_name)
        return
    end
    
    local si_node = SessionItem("si-node")

    if not si_node:configure({
        ["item.node"] = node,
    }) then
        Log:warning("Failed to configure si-node for " .. source_name)
        return
    end

    si_node:register()
    
    local node_info = {
        node = node,
        si_node = si_node,
        source_name = source_name,
        node_name = unique_name,
        connection_count = 1,
    }

    app_nodes[source_name] = node_info

    si_node:activate(Feature.SessionItem.ACTIVE)
end

source_om:connect("object-added", function(om, node)
    local properties = node.properties
    local source_name = properties["application.name"]

    if not app_nodes[source_name] then
        createAppSink(source_name)
    else
        app_nodes[source_name].connection_count = app_nodes[source_name].connection_count + 1
    end
end)

source_om:connect("object-removed", function(om, node)
    local source_name = node.properties["application.name"]
    local node_info = app_nodes[source_name]

    app_nodes[source_name].connection_count = app_nodes[source_name].connection_count - 1

    if node_info.connection_count <= 0 then
        if node_info.si_node then
            node_info.si_node:deactivate(Feature.SessionItem.ACTIVE)
        end

        if node_info.node then
            node_info.node:request_destroy()
        end

        app_nodes[source_name] = nil
    end
end)

source_om:activate()