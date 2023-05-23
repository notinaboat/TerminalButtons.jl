"""
# TerminalButtons.jl

Terminal-mode Push Buttons for Linux Touch Screens.

Create simple touch screen interfaces without X11.

Uses [LinuxTouchEvents.jl](https://github.com/notinaboat/LinuxTouchEvents.jl)
to get touch screen input (e.g from a
[Raspberry Pi Touch Display](https://www.raspberrypi.org/documentation/hardware/display/README.md)).

Uses [Terming.jl](https://github.com/foldfelis/Terming.jl) and
[Crayons.jl](https://github.com/KristofferC/Crayons.jl) to draw buttons.

![](buttons.png)
"""
module TerminalButtons

using LinuxTouchEvents
using Crayons
using UnixIO
using UnixIO.Debug
using Terming


struct Rect
    x::Int
    y::Int
    width::Int
    height::Int
end


function Base.in(p, r::Rect)
    x, y = p
    x >= r.x && x <= r.x + r.width &&
    y >= r.y && y <= r.y + r.height
end


mutable struct Button
    id::Any
    text::String
    style::Crayon
    active_style::Crayon
    shape::Union{Nothing,Rect}
    state::Union{Nothing,Symbol}
    function Button(id, text,
                    style = crayon"fg:white bg:blue",
                    active_style = crayon"fg:white bg:yellow") where T
        new(id, text, style, active_style, nothing, nothing)
    end
end


"""
    divide(x, n) -> [a, b, c ...]

Divide `x` into a `n`-element vector such that `sum(divide(x, n)) == x`
"""
function divide(x, n)
    d = x ÷ n
    err = x - (n * d)
    result = fill(d, n)
    for i in 1:err
        result[1 + (i-1) % n] += 1
    end
    result
end


function render_horizontal(io, buttons::Vector{Button}, shape::Rect)

    # Fit buttons evenly into available width...
    widths = divide(shape.width + 1, length(buttons))

    # Update shape of each button for touch detection...
    x = shape.x
    for (w, b) in zip(widths, buttons)
        b.shape = Rect(x, shape.y, w-1, shape.height)
        x += w
    end

    # Draw buttons...
    y = shape.y
    for i in 1:shape.height
        cmove(io, y, shape.x)
        for (j, b) in enumerate(buttons)
            j == 1 || print(io, " ")
            render_line(io, b, b.style, i)
        end
        y += 1
    end
end


function render_line(io, b::Button, style, row)
    print(io, style)
    if row == (b.shape.height + 1) ÷ 2
        # Draw Text on middle row,
        pad = b.shape.width - length(b.text)
        print(io, " "^(pad÷2), b.text, " "^(pad-(pad÷2)))
    else
        #...otherwise pad with spaces.
        print(io, " "^b.shape.width)
    end
    print(io, inv(style))
end


function render_vertical(io, buttons::Vector{Button}, shape::Rect)

    # Fit buttons evenly into available height...
    heights = divide(shape.height + 1, length(buttons))

    # Update shape of each button for touch detection...
    y = shape.y
    for (h, b) in zip(heights, buttons)
        b.shape = Rect(shape.x, y, shape.width, h-1)
        y += h
    end

    # Draw buttons...
    for (i, b) in enumerate(buttons)
        if i > 1
            cmove_line_down(io)
            clear_line(io)
        end
        draw_button(io, b)
    end
end


function draw_button(io, b::Button, style=b.style)
    y = b.shape.y
    for i in 1:b.shape.height
        cmove(io, y, b.shape.x)
        render_line(io, b, style, i)
        y += 1
    end
end


function select_button(io, buttons::Vector{Button}, touch)
    for b in buttons
        if touch in b.shape
            draw_button(io, b, b.active_style)
            return b
        end
    end
    return nothing
end

struct XTermEventChannel
    w::Int
    h::Int
    in::UnixIO.FD
    out::UnixIO.FD
    buffer::Channel{Any}
    function XTermEventChannel(in, out, w, h)
        @assert UnixIO.ispt(in) || UnixIO.iscanon(in)
        print(out, "\e[?1000h");
        return new(w, h, in, out, Channel{Any}(1))
    end
end

function Base.isready(t::XTermEventChannel; timeout=0)
    print(t.out, "\e[?1000h");
    if isempty(t.buffer)
        x = UnixIO.readavailable(t.in)
        if !isempty(x)
            x = String(x)
            if startswith(x, "\e[M")
                v = map(x->Int(x)-32, codeunits(x[4:end]))
                put!(t.buffer, (v[1], v[2]/t.w, v[3]/t.h))
            end
        end
    end

    return isready(t.buffer)
end

function Base.take!(t::XTermEventChannel)
    while true
        if isready(t)
            return take!(t.buffer)
        end
        Base.@lock t.in wait(t.in)
    end
end

function Base.close(t::XTermEventChannel)
    print("\e[?1000l");
    Terming.raw!(false)
end


"""
    choose_button(io, [id => button, ...]; vertical=false) -> selected_button

Draw a selection of buttons and wait for one of them to be pressed.

e.g.

    x = TerminalButtons.choose_button([1=>"Abort", 2=>"Retry", 3=>"Fail"])
    if x == 1
        ...
    elseif x == 2
        ...
    elseif x == 3
        ...
    end
"""
@db function choose_button(io, buttons;
                           vertical=false, rect=nothing, size=nothing,
                           touch_in=nothing)

    if size == nothing 
        size = UnixIO.tiocgwinsz(io)
        screen_h, screen_w = size.ws_row, size.ws_col
    else
        screen_h, screen_w = size
    end
                                                        @db 3 screen_h screen_w
    if rect == nothing
        if vertical
            rect = Rect(1, 1, screen_w, screen_h)
        else
            # Draw buttons across the bottom of the screen by default.
            button_h = 3
            rect = Rect(1, screen_h  + 1 - button_h, screen_w, button_h)
        end
    end

    # Draw buttons.
    buttons = [Button(id, text) for (id, text) in buttons]
    if vertical
        render_vertical(io, buttons, rect)
    else
        render_horizontal(io, buttons, rect)
    end

    # Wait for touch event.
    c = touch_in != nothing ? touch_in :
        Sys.islinux() ? TouchEventChannel() :
                        XTermEventChannel(screen_w, screen_h)          ;@db 3 c
    while true
        event = take!(c)
        if length(event) == 3 # FIXME
            event, x, y = event
        else
            x, y = event
        end
        x = round(Int, x * screen_w)
        y = round(Int, y * screen_h)

        # Select button at touch location.
        result = select_button(io, buttons, (x, y))
        if result != nothing
            if touch_in == nothing
                close(c)
            end
            @db return result.id
        end
    end
end

choose_button(io, v::Vector{String}; kw...) =
    choose_button(io, [x => x for x in v]; kw...)

choose_button(io, v::Vector{Pair{String,Function}}; kw...) =
    choose_button(io, [f => s for (s, f) in v]; kw...)()


# Documentation.

readme() = join([
    Docs.doc(@__MODULE__),
    "## Interface\n",
    Docs.@doc choose_button
   ], "\n\n")



end # module
