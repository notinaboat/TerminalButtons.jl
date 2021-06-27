"""
# TerminalButtons.jl

Terminal-mode Push Buttons for Linux Touch Screens.

Create simple touch screen interfaces without X11.

Uses [LinuxTouchEvents.jl](https://github.com/notinaboat/LinuxTouchEvents.jl)
to get touch screen input (e.g from a
[Raspberry Pi Touch Display](https://www.raspberrypi.org/documentation/hardware/display/README.md)).

Uses [TerminalUserInterfaces.jl](https://github.com/kdheepak/TerminalUserInterfaces.jl)
to draw buttons.

![](buttons.png)
"""
module TerminalButtons

using Crayons
using LinuxTouchEvents
import TerminalUserInterfaces.draw
using TerminalUserInterfaces
using TerminalUserInterfaces: Terminal, Buffer, Rect, Block, 
                              set, background, left, right, top, bottom,
                              terminal_size, flush


Base.@kwdef mutable struct Button
    text::String = "OK"
    rect::Rect = Rect()
    style::Crayon = crayon"fg:white bg:blue"
    selected::Bool = false
    f::Function = ()->nothing
end
Button(text) = Button(;text = text)


function draw(b::Button, buf::Buffer)
    x = b.rect.x + ((b.rect.width - length(b.text)) ÷ 2)
    y = b.rect.y + b.rect.height ÷ 2
    set(buf, x, y, b.text)
    background(buf, b.rect, b.style)
    if b.selected
        draw(Block(;border_style = b.style), b.rect, buf)
    end
end


function draw(b::Button, area::Rect, buf::Buffer)
    b.rect = area
    draw(b, buf)
end


function draw(buttons::Vector{Button}, rect::Rect, buf::Buffer)

    background(buf, rect, crayon"bg:dark_gray")

    l = length(buttons)
    button_w = (rect.width - (l-1)) ÷ l
    err = rect.width - (l-1) - (l * button_w)

    x = rect.x

    for b in buttons
        w = button_w + (err > 0 ? 1 : 0)
        err -= 1
        draw(b, Rect(x, rect.y, w - 1, rect.height), buf)
        x += w + 1
    end
end


contains(r::Rect, x, y) = x >= left(r) && x <= right(r) &&
                          y >= top(r) && y <= bottom(r)


function select(buttons::Vector{Button}, x, y)
    for b in buttons
        b.selected = false
    end
    for b in buttons
        if contains(b.rect, x, y)
            b.selected = true
            b.f()
            return b
        end
    end
    return nothing
end


"""
    choose_button([button, button, ...]) -> selected_button

Draw a selection of buttons and wait for one of them to be pressed.

e.g.

    TerminalUserInterfaces.initialize()

    t = TerminalUserInterfaces.Terminal()

    x = TerminalButtons.choose_button(t, ["Abort", "Retry", "Fail"])
    if x == "Abort"
        ...
    elseif x == "Retry"
        ...
    elseif x == "Fail"
        ...
    end

    TerminalUserInterfaces.cleanup()
"""
function choose_button(t, buttons; rect=nothing)

    screen_w, screen_h = terminal_size()

    # Draw buttons across the bottom of the screen by default.
    if rect == nothing
        button_h = 4
        rect = Rect(1, screen_h - button_h, screen_w, button_h)
    end

    # Draw buttons.
    buttons = Button.(buttons)
    draw(t, buttons, rect)
    flush(t)

    result = nothing
    while result == nothing

        # Wait for touch event.
        c = TouchEventChannel()
        x, y = take!(c)
        close(c)
        x = round(Int, x * screen_w)
        y = round(Int, y * screen_h)

        # Select button at touch location.
        result = select(buttons, x, y)

        # Redraw buttons in selected state.
        draw(t, buttons, rect)
        flush(t)
    end

    return result.text
end



# Documentation.

readme() = join([
    Docs.doc(@__MODULE__),
    "## Interface\n",
    Docs.@doc choose_button
   ], "\n\n")



end # module
