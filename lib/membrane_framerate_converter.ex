defmodule Membrane.FramerateConverter do
  @moduledoc """
  Element converts video to target constant frame rate, by dropping and duplicating frames as necessary.
  Input video may have constant or variable frame rate.
  Element expects each frame to be received in separate buffer.
  Additionally, presentation timestamps must be passed in each buffer's metadata.
  """

  use Bunch
  use Membrane.Filter

  alias Membrane.Buffer
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
        last_payload: nil,
        last_metadata: nil,
        target_pts: 0
      })

    {:ok, state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  def handle_process(:input, %{metadata: metadata}, _ctx, _state)
      when not is_map_key(metadata, :pts) do
    raise("cannot adjust framerate in stream without pts")
  end

  @impl true
  def handle_process(
        :input,
        %{payload: payload, metadata: metadata} = buffer,
        _ctx,
        %{last_payload: nil} = state
      ) do
    state =
      %{state | target_pts: metadata.pts, last_metadata: metadata, last_payload: payload}
      |> bump_target_pts()

    {{:ok, buffer: {:output, buffer}, redemand: :output}, state}
  end

  @impl true
  def handle_process(:input, %{payload: payload, metadata: metadata}, _ctx, state) do
    {buffers, state} = create_new_frames(metadata, payload, state)
    {{:ok, [buffer: {:output, buffers}, redemand: :output]}, state}
  end

  @impl true
  def handle_caps(:input, caps, _context, %{framerate: framerate} = state) do
    {{:ok, caps: {:output, %{caps | framerate: framerate}}}, state}
  end

  defp bump_target_pts(%{target_pts: pts, framerate: {num, denom}} = state) do
    use Ratio
    target_pts = pts + Ratio.new(denom * Membrane.Time.second(), num)
    %{state | target_pts: target_pts}
  end

  defp create_new_frames(metadata, payload, state, buffers \\ []) do
    use Ratio

    if Ratio.gt?(state.target_pts, metadata.pts) do
      state = %{
        state
        | last_metadata: metadata,
          last_payload: payload
      }

      {Enum.reverse(buffers), state}
    else
      dist_right = metadata.pts - state.target_pts
      dist_left = state.target_pts - state.last_metadata.pts

      buffer =
        if Ratio.lte?(dist_left, dist_right) do
          %Buffer{
            payload: state.last_payload,
            metadata: %{state.last_metadata | pts: state.target_pts}
          }
        else
          %Buffer{
            payload: payload,
            metadata: %{metadata | pts: state.target_pts}
          }
        end

      state = bump_target_pts(state)
      create_new_frames(metadata, payload, state, [buffer | buffers])
    end
  end
end
