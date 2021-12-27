defmodule Membrane.FramerateConverter do
  @moduledoc """
  Element converts video to target constant frame rate, by dropping and duplicating frames as necessary.
  Input video may have constant or variable frame rate.
  Element expects each frame to be received in separate buffer.
  Additionally, presentation timestamps must be passed in each buffer's `pts` fields.
  """

  use Bunch
  use Membrane.Filter

  alias Membrane.Caps.Video.Raw

  require Membrane.Logger

  def_options framerate: [
                spec: {pos_integer(), pos_integer()},
                default: {30, 1},
                description: """
                Target framerate.
                """
              ]

  def_output_pad :output,
    caps: {Raw, aligned: true}

  def_input_pad :input,
    caps: {Raw, aligned: true},
    demand_unit: :buffers

  @impl true
  def handle_init(%__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        last_buffer: nil,
        input_framerate: {0, 1},
        target_pts: 0,
        exact_target_pts: 0
      })

    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(
        :input,
        buffer,
        _ctx,
        %{last_buffer: nil} = state
      ) do
    state = put_first_buffer(buffer, state)
    state = bump_target_pts(state)

    {{:ok, buffer: {:output, buffer}, redemand: :output}, state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    {buffers, state} = create_new_frames(buffer, state)
    {{:ok, [buffer: {:output, buffers}, redemand: :output]}, state}
  end

  @impl true
  def handle_caps(:input, caps, _context, %{framerate: framerate} = state) do
    state = %{state | input_framerate: caps.framerate}

    {{:ok, caps: {:output, %{caps | framerate: framerate}}}, state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{input_framerate: {0, _denom}} = state) do
    {{:ok, end_of_stream: :output}, state}
  end

  def handle_end_of_stream(:input, _ctx, %{last_buffer: nil} = state) do
    {{:ok, end_of_stream: :output}, state}
  end

  @impl true
  def handle_end_of_stream(
        :input,
        _ctx,
        %{last_buffer: last_buffer} = state
      ) do
    input_frame_duration = get_frame_duration(state.input_framerate)
    output_frame_duration = get_frame_duration(state.framerate)
    # calculate last target timestamp so that the output video duration is closest to original
    best_last_timestamp = last_buffer.pts + input_frame_duration - div(output_frame_duration, 2)
    buffers = fill_to_last_timestamp(best_last_timestamp, state)
    {{:ok, [buffer: {:output, buffers}, end_of_stream: :output]}, state}
  end

  defp get_frame_duration({num, denom}) do
    round(Membrane.Time.second() * denom / num)
  end

  defp fill_to_last_timestamp(last_timestamp, state, buffers \\ []) do
    if state.target_pts > last_timestamp do
      Enum.reverse(buffers)
    else
      new_buffer = %{state.last_buffer | pts: state.target_pts}
      state = bump_target_pts(state)
      fill_to_last_timestamp(last_timestamp, state, [new_buffer | buffers])
    end
  end

  defp put_first_buffer(first_buffer, state) do
    %{
      state
      | target_pts: first_buffer.pts,
        exact_target_pts: first_buffer.pts,
        last_buffer: first_buffer
    }
  end

  defp bump_target_pts(%{exact_target_pts: exact_pts, framerate: {num, denom}} = state) do
    use Ratio
    next_exact_pts = exact_pts + Ratio.new(denom * Membrane.Time.second(), num)
    next_target_pts = Ratio.floor(next_exact_pts)
    %{state | target_pts: next_target_pts, exact_target_pts: next_exact_pts}
  end

  defp create_new_frames(input_buffer, state, buffers \\ []) do
    if state.target_pts > input_buffer.pts do
      state = %{state | last_buffer: input_buffer}

      {Enum.reverse(buffers), state}
    else
      last_buffer = state.last_buffer
      dist_right = input_buffer.pts - state.target_pts
      dist_left = state.target_pts - last_buffer.pts

      new_buffer =
        if dist_left <= dist_right do
          %{last_buffer | pts: state.target_pts}
        else
          %{input_buffer | pts: state.target_pts}
        end

      state = bump_target_pts(state)
      create_new_frames(input_buffer, state, [new_buffer | buffers])
    end
  end
end
