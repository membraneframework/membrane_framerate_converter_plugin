defmodule Membrane.FramerateConverterTest do
  @moduledoc """
  Tests for FramerateConverter module.
  """

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.Testing.Pipeline
  alias Membrane.H264.FFmpeg.{Parser, Decoder, Encoder}
  alias Membrane.File.{Sink, Source}
  require Membrane.Logger

  @testsrc Path.expand("fixtures/testsrc.h264", __DIR__)

  defp expand_path(file_name) do
    Path.expand("fixtures/#{file_name}", __DIR__)
  end

  defp prepare_output() do
    output_path = expand_path("output.h264")

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  describe "framreate converter should convert" do
    defp perform_test(elements, links) do
      pipeline_options = %Pipeline.Options{elements: elements, links: links}
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)

      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 5_000)
      Pipeline.stop_and_terminate(pid, blocking?: true)
    end

    test "video with pts" do
      output_path = prepare_output()

      elements = [
        file: %Source{chunk_size: 40_960, location: @testsrc},
        parser: %Parser{framerate: {10, 1}},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {2, 1}},
        encoder: Encoder,
        sink: %Sink{location: output_path}
      ]

      links = [
        link(:file)
        |> to(:parser)
        |> to(:decoder)
        |> to(:converter)
        |> to(:encoder)
        |> to(:sink)
      ]

      perform_test(elements, links)
    end
  end
end
