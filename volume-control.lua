-- for tracking
local apps = {}
local default_node_id = 0
local links = {}

default_port_in = nil

-- thanks to bennetthardwick for this awesome auto-connect-ports.lua script that helped me a lot
function linkPort(out_port, in_port, source_name)
    local link = Link("link-factory", {
        ["link.input.node"] = in_port.properties["node.id"],
        ["link.input.port"] = in_port.properties["object.id"],

        ["link.output.node"] = out_port.properties["node.id"],
        ["link.output.port"] = out_port.properties["object.id"],
        
        ["object.id"] = nil,
        ["object.linger"] = true,
        ["node.description"] = "Link for " .. source_name
    })

    link:activate(1, function(obj, error)
        if error then
            Log:warning("Failed to activate link '" .. source_name .. "': " .. tostring(error))
        end
    end)
    return link
end

function linkPorts(source_name)
    local app_data = apps[source_name]

    local source_port_out_om = ObjectManager {
        Interest {
            type = "port",
            Constraint { "object.path", "matches", source_name .. ":*" },
            Constraint { "port.direction", "=", "out" }
        }
    }

    local sink_port_in_om = ObjectManager {
        Interest {
            type = "port",
            Constraint { "object.path", "matches", "App-Sink-" .. source_name .. ":*" },
            Constraint { "port.direction", "=", "in" }
        }
    }

    local sink_port_out_om = ObjectManager {
        Interest {
            type = "port",
            Constraint { "object.path", "matches", "App-Sink-" .. source_name .. ":*" },
            Constraint { "port.direction", "=", "out" }
        }
    }

    function tryCreateLinks()
        for output in source_port_out_om:iterate {Constraint { "audio.channel", "equals", "FL"}} do
            for input in sink_port_in_om:iterate {Constraint { "audio.channel", "equals", "FL"}} do
                local link = linkPort(output, input, source_name)

                if link then
                    table.insert(links, link)
                end
            end
        end

        for output in source_port_out_om:iterate {Constraint { "audio.channel", "equals", "FR"}} do
            for input in sink_port_in_om:iterate {Constraint { "audio.channel", "equals", "FR"}} do
                local link = linkPort(output, input, source_name)

                if link then
                    table.insert(links, link)
                end
            end
        end

    end

    source_port_out_om:connect("object-added", tryCreateLinks)
    sink_port_in_om:connect("object-added", tryCreateLinks)
    sink_port_out_om:connect("object-added", tryCreateLinks)

    source_port_out_om:activate()
    sink_port_in_om:activate()
    sink_port_out_om:activate()
end

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
        ["node.virtual"] = false,
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
    
    local app_data = {
        node = node,
        si_node = si_node,
        source_name = source_name,
        node_name = unique_name,
        connection_count = 1,
    }

    apps[source_name] = app_data

    si_node:activate(Feature.SessionItem.ACTIVE)
end

source_om:connect("object-added", function(om, stream)
    local properties = stream.properties
    local source_name = properties["application.name"]

    if not apps[source_name] then
        createAppSink(source_name)
    else
        apps[source_name].connection_count = apps[source_name].connection_count + 1
    end

    linkPorts(source_name)
end)

source_om:connect("object-removed", function(om, stream)
    local source_name = stream.properties["application.name"]
    local node_info = apps[source_name]

    apps[source_name].connection_count = apps[source_name].connection_count - 1

    if node_info.connection_count <= 0 then
        if node_info.si_node then
            node_info.si_node:deactivate(Feature.SessionItem.ACTIVE)
        end

        if node_info.node then
            node_info.node:request_destroy()
        end

        apps[source_name] = nil
    end
end)

source_om:activate()