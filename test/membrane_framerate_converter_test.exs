defmodule Membrane.FramerateConverterTest do
  @moduledoc """
  Tests for FramerateConverter module.
  """

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.File.{Sink, Source}
  alias Membrane.H264.FFmpeg.{Parser, Decoder, Encoder}
  alias Membrane.Testing.Pipeline

  require Membrane.Logger

  @testsrc Path.expand("fixtures/testsrc_2s.h264", __DIR__)

  defp expand_path(file_name) do
    Path.expand("fixtures/#{file_name}", __DIR__)
  end

  defp prepare_output(file_name) do
    output_path = expand_path(file_name)

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  defp assert_files_equal(file_a, file_b) do
    assert {:ok, a} = File.read(file_a)
    assert {:ok, b} = File.read(file_b)
    assert a == b
  end

  describe "FramerateConverter should convert" do
    defp perform_test(elements) do
      pipeline_options = %Pipeline.Options{elements: elements}
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)

      assert Pipeline.play(pid) == :ok
      assert_end_of_stream(pid, :sink, :input, 5_000)
      Pipeline.stop_and_terminate(pid, blocking?: true)
    end

    test "video with pts" do
      output_path = prepare_output("out.h264")

      elements = [
        file: %Source{chunk_size: 40_960, location: @testsrc},
        parser: %Parser{framerate: {5, 1}},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {2, 1}},
        encoder: Encoder,
        sink: %Sink{location: output_path}
      ]

      perform_test(elements)
    end

    test "video to the same frame rate correctly" do
      output_path = prepare_output("out_2_fps.yuv")
      reference_file = expand_path("reference-testsrc_2_fps.yuv")

      elements = [
        file: %Source{chunk_size: 40_960, location: @testsrc},
        parser: %Parser{framerate: {5, 1}},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {2, 1}},
        sink: %Sink{location: output_path}
      ]

      perform_test(elements)
      assert_files_equal(output_path, reference_file)
    end

    test "video to lower frame rate correctly" do
      output_path = prepare_output("out_5_fps.yuv")
      reference_file = expand_path("reference-testsrc_5_fps.yuv")

      elements = [
        file: %Source{chunk_size: 40_960, location: @testsrc},
        parser: %Parser{framerate: {5, 1}},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {5, 1}},
        sink: %Sink{location: output_path}
      ]

      perform_test(elements)
      assert_files_equal(output_path, reference_file)
    end

    test "video to higher frame rate correctly" do
      output_path = prepare_output("out_15_fps.yuv")
      reference_file = expand_path("reference-testsrc_15_fps.yuv")

      elements = [
        file: %Source{chunk_size: 40_960, location: @testsrc},
        parser: %Parser{framerate: {5, 1}},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {15, 1}},
        sink: %Sink{location: output_path}
      ]

      perform_test(elements)
      assert_files_equal(output_path, reference_file)
    end
  end
end
