# TerminalButtons.jl

Terminal-mode Push Buttons for Linux Touch Screens.

Create simple touch screen interfaces without X11.

Uses [LinuxTouchEvents.jl](https://github.com/notinaboat/LinuxTouchEvents.jl) to get touch screen input (e.g from a [Raspberry Pi Touch Display](https://www.raspberrypi.org/documentation/hardware/display/README.md)).

Uses [Terming.jl](https://github.com/foldfelis/Terming.jl) and [Crayons.jl](https://github.com/KristofferC/Crayons.jl) to draw buttons.

![](buttons.png)


## Interface


```
choose_button([id => button, ...]; vertical=false) -> selected_button
```

Draw a selection of buttons and wait for one of them to be pressed.

e.g.

```
x = TerminalButtons.choose_button([1=>"Abort", 2=>"Retry", 3=>"Fail"])
if x == 1
    ...
elseif x == 2
    ...
elseif x == 3
    ...
end
```

