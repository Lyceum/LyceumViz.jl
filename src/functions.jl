####
#### PhysicsState
####

resettime!(phys::PhysicsState) = (reset!(phys.timer); phys.elapsedsim = 0; phys)


####
#### UIState
####

function alignscale!(ui::UIState, sim::MJSim)
    ui.cam[].lookat = sim.m.stat.center
    ui.cam[].distance = 1.5 * sim.m.stat.extent
    ui.cam[].type = MJCore.mjCAMERA_FREE
    return ui
end

####
#### Engine
####

@inline mode(e::Engine, idx::Integer = e.curmodeidx) = e.modes[idx]

function switchmode!(e::Engine, idx::Integer)
    io = e.ui.miscbuf
    seekstart(io)

    teardown!(e.ui, e.phys, mode(e))
    deregister!(e.mngr, e.modehandlers...)

    e.curmodeidx = idx
    e.modehandlers = handlers(e.ui, e.phys, mode(e))
    setup!(e.ui, e.phys, mode(e))
    register!(e.mngr, e.modehandlers...)
    writedescription!(io, e.modehandlers)
    e.modehandlerdescription = String(take!(io))

    return e
end


function printhelp(e::Engine)
    io = e.ui.io1

    writedescription(io, e.handlers)
    handlerdescription = String(take!(io))

    writedescription(io, e.modehandlers)
    modehandlerdescription = String(take!(io))

    println("Standard Commands:")
    print(handlerdescription)
    if !isempty(modehandlerdescription)
        println("$(nameof(mode(e))) Mode Commands:")
        print(modehandlerdescription)
    end
    println()
    println()

    return
end

function writedescription(io, hs::Vector{EventHandler})
    if !isempty(hs)
        whens = String[]
        whats = String[]
        for h in hs
            if h.when !== nothing && h.what !== nothing
                push!(whens, h.when)
                push!(whats, h.what)
            elseif h.what !== nothing
                push!(whens, "----")
                push!(whats, h.what)
            end
        end

        header = ["Command", "Description"]
        _, ncols = get_terminalsize()
        w1max = max(maximum(length, whens), length(first(header)))
        w2max = max(maximum(length, whats), length(first(header)))

        w1 = min(w1max, div(ncols, 2))
        w2 = min(w2max, ncols - w1 - 4 * length(header)) # each column is padded by 4 spaces
        pretty_table(io, hcat(whens, whats), ["Command", "Description"], alignment = :L, linebreaks = true, autowrap = true, columns_width = [w1, w2])
    end

    return
end


function overlay_info(rect::MJCore.mjrRect, e::Engine)
    ui = e.ui
    io1 = ui.io1
    io2 = ui.io2
    phys = e.phys
    sim = getsim(phys.model)

    seekstart(io1)
    seekstart(io2)

    println(io1, "Mode")
    println(io2, nameof(mode(e)))

    println(io1, "Status")
    if ui.paused
        println(io2, "Paused")
    elseif ui.reversed
        println(io2, "Reverse Simulation")
    else
        println(io2, "Forward Simulation")
    end

    println(io1, "Time")
    @printf io2 "%.3f s\n" time(sim)

    println(io1, "Refresh Rate")
    @printf io2 "%d Hz\n" ui.refreshrate

    println(io1, "Sim Speed")
    if ui.speedmode
        if ui.speedfactor < 1
            @printf io2 "%.5gx (slower)\n" 1 / ui.speedfactor
        else
            @printf io2 "%.5gx (faster)\n" ui.speedfactor
        end
    else
        println(io2, "1")
    end

    println(io1, "Frame")
    println(io2, MJCore.mjFRAMESTRING[e.ui.vopt[].frame+1])

    println(io1, "Label")
    println(io2, MJCore.mjLABELSTRING[e.ui.vopt[].label+1])

    # env specific info
    if phys.model isa AbstractMuJoCoEnvironment
        name = string(Base.nameof(typeof(phys.model)))
        println(io1, "Env")
        println(io2, name)

        println(io1, "Reward")
        @printf io2 "%.5g\n" ui.reward

        println(io1, "Eval")
        @printf io2 "%.5g\n" ui.eval
    end

    # mode specific info
    println(io1, "Mode Info")
    println(io2)
    modeinfo(io1, io2, ui, phys, mode(e))

    info1 = string(chomp(String(take!(io1))))
    info2 = string(chomp(String(take!(io2))))

    mjr_overlay(
        MJCore.FONT_NORMAL,
        MJCore.GRID_BOTTOMLEFT,
        rect,
        info1,
        info2,
        ui.con,
    )

function writedescription!(io, handlers::Vector{<:AbstractEventHandler})
    for handler in handlers
        !isnothing(handler.description) && println(io, handler.description)
    end
    io
end


function startrecord!(e::Engine)
    window = e.mngr.state.window
    SetWindowAttrib(window, GLFW.RESIZABLE, 0)
    w, h = GLFW.GetFramebufferSize(window)
    resize!(e.framebuf, 3 * w * h)
    e.ffmpeghandle, dst = startffmpeg(w, h, GetRefreshRate())
    @info "Saving video to $dst. Window resizing temporarily disabled"
    e
end

function recordframe!(e::Engine, rect)
    mjr_readPixels(e.framebuf, C_NULL, rect, e.ui.con)
    write(e.ffmpeghandle, e.framebuf)
    e
end

function stoprecord!(e::Engine)
    close(e.ffmpeghandle)
    SetWindowAttrib(e.mngr.state.window, GLFW.RESIZABLE, 1)
    e.ffmpeghandle = nothing
    @info "Finished! Window resizing re-enabled."
    e
end