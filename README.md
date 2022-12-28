# Membrane Framerate Converter Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_framerate_converter_plugin.svg)](https://hex.pm/packages/membrane_framerate_converter_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_framerate_converter_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_framerate_converter_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_framerate_converter_plugin)

Plugin providing element for converting frame rate of raw video stream.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_framerate_converter_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_framerate_converter_plugin, "~> 0.6.0"}
  ]
end
```

## Description

Element converts video to target constant frame rate, by dropping and duplicating frames as necessary
(input video may have constant or variable frame rate).

## Usage

Example converting h264 video from 10 to 2 fps.

```elixir
defmodule Pipeline do
  use Membrane.Pipeline

  alias Membrane.H264.FFmpeg.{Parser, Decoder, Encoder}
  alias Membrane.File.{Sink, Source}

  @impl true
  def handle_init(_ctx, filename) do
    structure =
        child(file: %Source{chunk_size: 40_960, location: filename})
        |> child(parser: %Parser{framerate: {10, 1}})
        |> child(decoder: Decoder)
        |> child(converter: %Membrane.FramerateConverter{framerate: {2, 1}})
        |> child(encoder: Encoder)
        |> child(sink: %Sink{location: "output.h264"})

    {[structure: structure], %{}}
  end
end
```

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_framerate_converter_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_framerate_converter_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
