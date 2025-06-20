local mixers = {}

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

    link:activate(1)

    return link
end

source_om = ObjectManager {
    Interest {
        type = "node",
        Constraint {"media.class", "equals", "Stream/Output/Audio"}
    }
}

source_om:connect("object-added", function(_, source)
    Log:warning("source called" .. source.properties["node.name"])

    local source_name = source.properties["application.name"]
    local unique_name = "AudioMixer-" .. source_name:gsub("[^%w]", "-")
    local description = "Volume Control for " .. source_name

    if not mixers[source_name] then
        node = Node("adapter", {
            ["factory.name"] = "support.null-audio-sink",
            ["node.name"] = unique_name,
            ["node.description"] = description,
            ["media.class"] = "Audio/Sink",
            ["audio.channels"] = 2,
            ["audio.position"] = "[ FL FR ]",
            ["node.virtual"] = "true",
            ["device.monitor"]   = "true",
            
            --this enables the volume control for the sink
            ["monitor.channel-volumes"] = "true"
        })

        si_node = SessionItem("si-node")

        if not si_node:configure({
            ["item.node"] = node,
        }) then
            Log:warning("Failed to configure si-node for " .. source_name)
        end

        si_node:register()

        local node_info = {
            node = node,
            source_name = source_name,
            node_name = "AudioMixer-" .. unique_name,
            links = {}
        }

        mixers[source_name] = node_info

        si_node:activate(Features.ALL)
    end

    mixer_om = ObjectManager {
        Interest {
            type = "node",
            Constraint {"media.class", "equals", "Audio/Sink"},
            Constraint {"node.name", "equals", "AudioMixer-" .. source.properties["node.name"]}
        }
    }

    mixer_om:connect("object-added", function(_, mixer)
        Log:warning("mixer called")

        link_om = ObjectManager {
            Interest {
                type = "link",
                Constraint {"link.output.node", "equals", tostring(source["bound-id"])},
                Constraint {"link.input.node", "not-equals", tostring(mixer["bound-id"])}
            }
        }

        link_om:connect("object-added", function(_, link)
            Log:warning("link called")
            
            -- get the output sink of the source
            sink_om = ObjectManager {
                Interest {
                    type = "node",
                    Constraint {"object.id", "equals", tostring(link.properties["link.input.node"])},
                }
            }

            sink_om:connect("object-added", function(_, sink)
                Log:warning("sink called: ")
                -- now we have access to the source, mixer, old links and the output sink
                -- let the rerouting begin!!

                -- delete the old links
                for _, l in pairs(mixers[source_name].links) do
                    l:request_destroy()
                end

                for source_out in source:iterate_ports { Constraint { "port.direction", "equals", "out"}, Constraint { "audio.channel", "equals", "FL"} } do
                    for mixer_in in mixer:iterate_ports { Constraint {"port.direction", "equals", "in"}, Constraint { "audio.channel", "equals", "FL"} } do
                        local l = linkPort(source_out, mixer_in, source_name)
                        table.insert(mixers[source_name].links, l)
                    end
                end

                for source_out in source:iterate_ports { Constraint { "port.direction", "equals", "out"}, Constraint { "audio.channel", "equals", "FR"} } do
                    for mixer_in in mixer:iterate_ports { Constraint {"port.direction", "equals", "in"}, Constraint { "audio.channel", "equals", "FR"} } do
                        local l = linkPort(source_out, mixer_in, source_name)
                        table.insert(mixers[source_name].links, l)
                    end
                end

                for mixer_out in mixer:iterate_ports { Constraint { "port.direction", "equals", "out"}, Constraint { "audio.channel", "equals", "FL"} } do
                    for sink_in in sink:iterate_ports { Constraint {"port.direction", "equals", "in"}, Constraint { "audio.channel", "equals", "FL"} } do
                        local l = linkPort(mixer_out, sink_in, source_name)
                        table.insert(mixers[source_name].links, l)
                    end
                end

                for mixer_out in mixer:iterate_ports { Constraint { "port.direction", "equals", "out"}, Constraint { "audio.channel", "equals", "FR"} } do
                    for sink_in in sink:iterate_ports { Constraint {"port.direction", "equals", "in"}, Constraint { "audio.channel", "equals", "FR"} } do
                        local l = linkPort(mixer_out, sink_in, source_name)
                        table.insert(mixers[source_name].links, l)
                    end
                end
            end)

            -- destroy the link that connects the output node with the sink
            link:request_destroy()

            sink_om:activate()
        end)

        link_om:activate()
    end)

    mixer_om:activate()
end)


source_om:activate()
