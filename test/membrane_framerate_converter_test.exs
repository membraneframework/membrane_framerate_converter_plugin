defmodule Membrane.FramerateConverterTest do
  @moduledoc """
  Tests for FramerateConverter module.
  """

  use ExUnit.Case
  use Membrane.Pipeline

  import Membrane.Testing.Assertions

  alias Membrane.File.{Sink, Source}
  alias Membrane.H264.FFmpeg.{Decoder, Encoder, Parser}
  alias Membrane.Testing
  alias Membrane.Testing.Pipeline

  require Membrane.Logger

  @fps_test_file Path.expand("fixtures/testsrc_5_fps.h264", __DIR__)
  @timestamp_test_file Path.expand("fixtures/10-720p.h264", __DIR__)
  @fps_file_framerate {5, 1}
  @timestamp_file_framerate {30, 1}

  defp expand_path(file_name) do
    Path.expand("fixtures/#{file_name}", __DIR__)
  end

  defp prepare_output(file_name) do
    output_path = expand_path(file_name)

    File.rm(output_path)
    on_exit(fn -> File.rm(output_path) end)

    output_path
  end

  defp count_frames(video_path) do
    with {result_str, 0} <-
           System.cmd(
             "ffprobe",
             [
               # set logging level
               "-v",
               "error",
               # report number of frames
               "-count_frames",
               # show information only about number of frames
               "-show_entries",
               "stream=nb_read_frames",
               # set output format (hide description and only show value)
               "-of",
               "csv=p=0",
               video_path
             ]
           ),
         {frames, _rest} <- Integer.parse(result_str) do
      frames
    end
  end

  describe "FramerateConverter should" do
    defp perform_general_test(elements) do
      pipeline_options = %Pipeline.Options{elements: elements}
      assert {:ok, pid} = Pipeline.start_link(pipeline_options)

      assert_end_of_stream(pid, :sink, :input, 2_000)
      Pipeline.terminate(pid, blocking?: true)
    end

    defp perform_fps_test(output_filename, target_frame_count, target_framerate) do
      output_path = prepare_output(output_filename)

      elements = [
        file: %Source{chunk_size: 40_960, location: @fps_test_file},
        parser: %Parser{framerate: @fps_file_framerate},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: target_framerate},
        encoder: Encoder,
        sink: %Sink{location: output_path}
      ]

      perform_general_test(elements)
      output_frames = count_frames(output_path)
      assert output_frames == target_frame_count
    end

    test "convert video with given pts" do
      output_path = prepare_output("out.h264")

      elements = [
        file: %Source{chunk_size: 40_960, location: @fps_test_file},
        parser: %Parser{framerate: @fps_file_framerate},
        decoder: Decoder,
        converter: %Membrane.FramerateConverter{framerate: {30_000, 1001}},
        encoder: Encoder,
        sink: %Sink{location: output_path}
      ]

      perform_general_test(elements)
    end

    test "convert video to the lower frame rate correctly" do
      perform_fps_test("out_2_fps.h264", 4, {2, 1})
    end

    test "convert video to same frame rate correctly" do
      perform_fps_test("out_5_fps.h264", 10, {5, 1})
    end

    test "convert video to higher frame rate correctly" do
      perform_fps_test("out_15_fps.h264", 30, {15, 1})
    end

    test "convert video to the complicated frame rate correctly" do
      perform_fps_test("out_complicated_fps.h264", 60, {30_000, 1001})
    end

    test "append correct timestamps" do
      target_framerate = {15, 1}
      target_frame_count = 5
      target_frame_duration = Ratio.div(Membrane.Time.second(), 15)

      pipeline = %Pipeline.Options{
        elements: [
          file: %Source{chunk_size: 40_960, location: @timestamp_test_file},
          parser: %Parser{framerate: @timestamp_file_framerate},
          decoder: Decoder,
          converter: %Membrane.FramerateConverter{framerate: target_framerate},
          sink: Testing.Sink
        ]
      }

      assert {:ok, pid} = Pipeline.start_link(pipeline)

      0..(target_frame_count - 1)
      |> Enum.each(fn i ->
        expected_pts = i |> Ratio.mult(target_frame_duration) |> Ratio.floor()
        assert_sink_buffer(pid, :sink, %Membrane.Buffer{pts: pts})
        assert expected_pts == pts
      end)

      Testing.Pipeline.terminate(pid, blocking?: true)
    end
  end
end
